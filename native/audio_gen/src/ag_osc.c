#include "ag_osc.h"
#include <math.h>
#include <string.h>

void ag_osc_init(AgOsc *osc, AgOscType type, double sr) {
    memset(osc, 0, sizeof(*osc));
    osc->type = type;
    osc->sr = sr > 0 ? sr : AG_SR_DEFAULT;
    osc->freq = 440.0;
    osc->pw = 0.5;
    osc->phase = 0.0;
    osc->phase2 = 0.13;
    osc->detune = 0.0;
    ag_rng_seed(&osc->rng, 0x1234 + (uint64_t)type*100);
}
void ag_osc_set_freq(AgOsc *osc, double freq) {
    if (freq < 0.05) freq = 0.05;
    double nyq = osc->sr * 0.495;
    if (freq > nyq) freq = nyq;
    osc->freq = freq;
}
void ag_osc_set_type(AgOsc *osc, AgOscType type) { osc->type = type; }
void ag_osc_set_pw(AgOsc *osc, double pw) { osc->pw = ag_clamp_d(pw, 0.005, 0.995); }
void ag_osc_reset(AgOsc *osc) { osc->phase = 0.0; osc->phase2=0.13; osc->last_out=0; osc->tri_state=0; osc->tri_last=0; }
void ag_osc_set_detune(AgOsc *osc, double cents) { osc->detune = cents; }

float ag_osc_sine_f(float phase01) {
    return sinf(phase01 * (float)AG_TAU);
}
float ag_osc_saw_f(float phase01) {
    return phase01 * 2.0f - 1.0f;
}
float ag_osc_square_f(float phase01, float pw) {
    return phase01 < pw ? 1.0f : -1.0f;
}
float ag_osc_tri_f(float phase01) {
    float v = phase01 < 0.5f ? phase01 * 4.0f - 1.0f : 3.0f - phase01 * 4.0f;
    return v;
}

/* 2nd order polyBLEP */
float ag_poly_blep(float t, float dt) {
    if (t < dt) {
        t /= dt;
        return t+t - t*t - 1.0f;
    } else if (t > 1.0f - dt) {
        t = (t - 1.0f) / dt;
        return t*t + t+t + 1.0f;
    }
    return 0.0f;
}
/* 4th order - much cleaner */
float ag_poly_blep_4(float t, float dt) {
    if (t < dt) {
        t /= dt;
        float t2 = t*t;
        float t3 = t2*t;
        return -t3*0.5f + t2 + t*0.5f - 1.0f;
    } else if (t > 1.0f - dt) {
        t = (t - 1.0f) / dt;
        float t2 = t*t;
        float t3 = t2*t;
        return t3*0.5f + t2 + t*0.5f + 1.0f;
    }
    return 0.0f;
}
float ag_poly_blamp(float t, float dt) {
    /* integrated BLEP for triangle */
    if (t < dt) {
        t /= dt;
        float t2 = t*t;
        float t3 = t2*t;
        float t4 = t3*t;
        return t4*0.25f - t3*0.6666667f + t2*0.5f - 0.0833333f;
    } else if (t > 1.0f - dt) {
        t = (t - 1.0f) / dt;
        float t2 = t*t;
        float t3 = t2*t;
        float t4 = t3*t;
        return -t4*0.25f + t3*0.6666667f - t2*0.5f + t*0.5f + 0.0833333f;
    }
    return 0.0f;
}

float ag_osc_next_raw(AgOsc *osc) {
    double ph = osc->phase;
    float out = 0.0f;
    switch (osc->type) {
        case AG_OSC_SINE: out = sinf((float)(ph * AG_TAU)); break;
        case AG_OSC_SAW: out = (float)(ph * 2.0 - 1.0); break;
        case AG_OSC_SQUARE: out = ph < osc->pw ? 1.0f : -1.0f; break;
        case AG_OSC_TRI: {
            out = ph < 0.5 ? (float)(ph * 4.0 - 1.0) : (float)(3.0 - ph * 4.0);
        } break;
        case AG_OSC_NOISE: out = ag_rng_range_f32(&osc->rng, -1.0f, 1.0f); break;
        case AG_OSC_PULSE: out = ph < osc->pw ? 1.0f : -1.0f; break;
        case AG_OSC_SAW_TRI: {
            float saw = (float)(ph * 2.0 - 1.0);
            float tri = ph < 0.5 ? (float)(ph * 4.0 - 1.0) : (float)(3.0 - ph * 4.0);
            out = saw * 0.5f + tri * 0.5f;
        } break;
        case AG_OSC_SAW2: {
            float saw1 = (float)(ph * 2.0 - 1.0);
            float saw2 = (float)(osc->phase2 * 2.0 - 1.0);
            out = (saw1 + saw2)*0.5f;
        } break;
        case AG_OSC_SUPERSAW: {
            /* quick supersaw: 7 detuned saws */
            float sum=0;
            double detune_cents[7] = {-12, -7, -3, 0, 3, 7, 12};
            for(int i=0;i<7;i++){
                double det = pow(2.0, detune_cents[i]/1200.0 * (osc->detune>0?osc->detune/10.0:0.7));
                double ph_i = fmod(ph * det + i*0.13, 1.0);
                sum += (float)(ph_i*2.0 -1.0);
            }
            out = sum * 0.142857f;
        } break;
        default: out = sinf((float)(ph * AG_TAU)); break;
    }
    double inc = osc->freq / osc->sr;
    if(osc->type==AG_OSC_SAW2 || osc->type==AG_OSC_SUPERSAW){
        double det2 = pow(2.0, osc->detune/1200.0);
        if(det2<0.9) det2=0.9;
        if(det2>1.2) det2=1.2;
        osc->phase2 += inc * det2;
        if (osc->phase2 >= 1.0) osc->phase2 -= 1.0;
    }
    osc->phase += inc;
    if (osc->phase >= 1.0) osc->phase -= 1.0;
    return out;
}

/* HQ with 4th order BLEP + DPW triangle + DC blocker */
float ag_osc_next(AgOsc *osc) {
    if (osc->type == AG_OSC_SINE || osc->type == AG_OSC_NOISE) {
        return ag_osc_next_raw(osc);
    }
    double ph = osc->phase;
    double dt = osc->freq / osc->sr;
    float out = 0.0f;
    switch (osc->type) {
        case AG_OSC_SAW: {
            out = (float)(ph * 2.0 - 1.0);
            out -= ag_poly_blep_4((float)ph, (float)dt);
            /* DC blocker */
            float dc = out - osc->dc_block_x1 + 0.995f*osc->dc_block_y1;
            osc->dc_block_x1=out;
            osc->dc_block_y1=dc;
            out=dc;
        } break;
        case AG_OSC_SQUARE:
        case AG_OSC_PULSE: {
            out = ph < osc->pw ? 1.0f : -1.0f;
            out += ag_poly_blep_4((float)ph, (float)dt);
            double ph2 = ph - osc->pw;
            if (ph2 < 0) ph2 += 1.0;
            out -= ag_poly_blep_4((float)ph2, (float)dt);
            float dc = out - osc->dc_block_x1 + 0.995f*osc->dc_block_y1;
            osc->dc_block_x1=out;
            osc->dc_block_y1=dc;
            out=dc;
        } break;
        case AG_OSC_TRI: {
            /* DPW triangle: differentiate square then integrate with leak */
            float sq = ph < osc->pw ? 1.0f : -1.0f;
            /* naive square with BLEP */
            float sq_blep = sq;
            sq_blep += ag_poly_blep_4((float)ph, (float)dt);
            double ph2 = ph - osc->pw;
            if (ph2 < 0) ph2 += 1.0;
            sq_blep -= ag_poly_blep_4((float)ph2, (float)dt);
            /* DPW: triangle is integral of square */
            float tri = sq_blep * (float)dt + osc->tri_state;
            osc->tri_state = tri;
            /* leaky integrator to remove DC drift and shape */
            tri = tri - osc->tri_last*0.998f;
            osc->tri_last = tri;
            /* scale */
            out = tri * 4.0f;
            /* soft clip for triangle shape */
            out = ag_clamp_f(out, -1.0f, 1.0f);
        } break;
        case AG_OSC_SAW2: {
            /* two saws with BLEP */
            float saw1 = (float)(ph*2.0-1.0) - ag_poly_blep_4((float)ph, (float)dt);
            double dt2 = dt * pow(2.0, osc->detune/1200.0);
            float saw2 = (float)(osc->phase2*2.0-1.0) - ag_poly_blep_4((float)osc->phase2, (float)dt2);
            out = (saw1 + saw2)*0.5f;
            float dc = out - osc->dc_block_x1 + 0.995f*osc->dc_block_y1;
            osc->dc_block_x1=out;
            osc->dc_block_y1=dc;
            out=dc;
        } break;
        case AG_OSC_SUPERSAW: {
            float sum=0;
            double base_dt = dt;
            double detune_cents[7] = {-12, -7, -3, 0, 3, 7, 12};
            for(int i=0;i<7;i++){
                double det = pow(2.0, detune_cents[i]/1200.0 * (osc->detune>0?osc->detune/10.0:0.7));
                double ph_i = fmod(ph * det + i*0.13, 1.0);
                double dt_i = base_dt * det;
                float saw = (float)(ph_i*2.0-1.0) - ag_poly_blep_4((float)ph_i, (float)dt_i);
                sum+=saw;
            }
            out = sum * 0.142857f;
            float dc = out - osc->dc_block_x1 + 0.995f*osc->dc_block_y1;
            osc->dc_block_x1=out;
            osc->dc_block_y1=dc;
            out=dc;
        } break;
        default: out = ag_osc_next_raw(osc); return out;
    }
    double inc = osc->freq / osc->sr;
    if(osc->type==AG_OSC_SAW2 || osc->type==AG_OSC_SUPERSAW){
        double det2 = pow(2.0, osc->detune/1200.0);
        if(det2<0.9) det2=0.9;
        if(det2>1.2) det2=1.2;
        osc->phase2 += inc * det2;
        if (osc->phase2 >= 1.0) osc->phase2 -= 1.0;
    }
    osc->phase += inc;
    if (osc->phase >= 1.0) osc->phase -= 1.0;
    return out;
}

float ag_osc_next_hq(AgOsc *osc) {
    /* 2x oversampled */
    if(osc->type==AG_OSC_SINE || osc->type==AG_OSC_NOISE) return ag_osc_next(osc);
    double dt = osc->freq / osc->sr;
    /* oversample 2x */
    double ph = osc->phase;
    float out1=0,out2=0;
    /* first sub-sample */
    switch(osc->type){
        case AG_OSC_SAW: out1 = (float)(ph*2.0-1.0) - ag_poly_blep_4((float)ph, (float)(dt*0.5)); break;
        case AG_OSC_SQUARE: {
            out1 = ph < osc->pw ? 1.0f : -1.0f;
            out1 += ag_poly_blep_4((float)ph, (float)(dt*0.5));
            double ph2=ph-osc->pw; if(ph2<0) ph2+=1.0;
            out1 -= ag_poly_blep_4((float)ph2, (float)(dt*0.5));
        } break;
        default: out1 = ag_osc_next(osc); return out1;
    }
    ph += dt*0.5;
    if(ph>=1.0) ph-=1.0;
    switch(osc->type){
        case AG_OSC_SAW: out2 = (float)(ph*2.0-1.0) - ag_poly_blep_4((float)ph, (float)(dt*0.5)); break;
        case AG_OSC_SQUARE: {
            out2 = ph < osc->pw ? 1.0f : -1.0f;
            out2 += ag_poly_blep_4((float)ph, (float)(dt*0.5));
            double ph2=ph-osc->pw; if(ph2<0) ph2+=1.0;
            out2 -= ag_poly_blep_4((float)ph2, (float)(dt*0.5));
        } break;
        default: out2=out1; break;
    }
    osc->phase += dt;
    if(osc->phase>=1.0) osc->phase-=1.0;
    return (out1+out2)*0.5f;
}

/* Wavetable HQ */
void ag_wt_sine(AgWavetable *wt) {
    for (int i=0;i<AG_WT_SIZE;i++) {
        float v = sinf((float)i / AG_WT_SIZE * (float)AG_TAU);
        wt->table[i]=v;
        wt->table_hf[i]=v;
    }
}
void ag_wt_saw(AgWavetable *wt) {
    for (int i=0;i<AG_WT_SIZE;i++){
        float v = (float)i / AG_WT_SIZE * 2.0f - 1.0f;
        wt->table[i]=v;
    }
    /* bandlimited HF version: reduce high harmonics */
    for(int i=0;i<AG_WT_SIZE;i++){
        float ph = (float)i/AG_WT_SIZE;
        float sum=0;
        for(int h=1;h<=16;h++){
            sum += sinf(ph*AG_TAU*h) / h * 0.5f;
        }
        wt->table_hf[i]=sum * 0.6f;
    }
}
void ag_wt_square(AgWavetable *wt, float pw) {
    for (int i=0;i<AG_WT_SIZE;i++) wt->table[i] = ((float)i / AG_WT_SIZE) < pw ? 1.0f : -1.0f;
    for(int i=0;i<AG_WT_SIZE;i++){
        float ph = (float)i/AG_WT_SIZE;
        float sum=0;
        for(int h=1;h<=16;h+=2){
            sum += sinf(ph*AG_TAU*h) / h;
        }
        wt->table_hf[i]=sum * 0.8f;
    }
}
void ag_wt_tri(AgWavetable *wt) {
    for (int i=0;i<AG_WT_SIZE;i++) {
        float ph = (float)i / AG_WT_SIZE;
        wt->table[i] = ph < 0.5f ? ph*4.0f-1.0f : 3.0f - ph*4.0f;
        wt->table_hf[i]=wt->table[i];
    }
}
void ag_wt_morph(AgWavetable *out, const AgWavetable *a, const AgWavetable *b, float mix) {
    mix = ag_clamp_f(mix, 0.0f, 1.0f);
    for (int i=0;i<AG_WT_SIZE;i++){
        out->table[i] = a->table[i]*(1.0f-mix) + b->table[i]*mix;
        out->table_hf[i] = a->table_hf[i]*(1.0f-mix) + b->table_hf[i]*mix;
    }
}
void ag_wt_bandlimit(AgWavetable *wt, double sr, double max_freq) {
    (void)sr; (void)max_freq;
    /* simple low-pass the wavetable for high freq */
    float last=wt->table[0];
    for(int i=0;i<AG_WT_SIZE;i++){
        float cur=wt->table[i];
        float filtered = last*0.5f + cur*0.5f;
        wt->table_hf[i]=filtered;
        last=filtered;
    }
}
void ag_wt_osc_init(AgWTOsc *osc, const AgWavetable *wt, double sr) {
    memset(osc,0,sizeof(*osc));
    if (wt) osc->wt = *wt; else ag_wt_sine(&osc->wt);
    osc->sr = sr>0?sr:AG_SR_DEFAULT;
    osc->freq = 440.0;
    osc->phase = 0.0;
    osc->interp=0.0f;
}
static inline float cubic_interp(float y0, float y1, float y2, float y3, float mu) {
    float a0 = y3 - y2 - y0 + y1;
    float a1 = y0 - y1 - a0;
    float a2 = y2 - y0;
    float a3 = y1;
    return a0*mu*mu*mu + a1*mu*mu + a2*mu + a3;
}
float ag_wt_osc_next(AgWTOsc *osc) {
    double ph = osc->phase * AG_WT_SIZE;
    int i0 = (int)ph;
    int i1 = (i0+1) & AG_WT_SIZE_MASK;
    float frac = (float)(ph - (double)i0);
    float *tbl = osc->freq > osc->sr*0.15 ? osc->wt.table_hf : osc->wt.table;
    float a = tbl[i0 & AG_WT_SIZE_MASK];
    float b = tbl[i1];
    float out = a + (b-a)*frac;
    osc->phase += osc->freq / osc->sr;
    if (osc->phase >= 1.0) osc->phase -= 1.0;
    return out;
}
float ag_wt_osc_next_cubic(AgWTOsc *osc) {
    double ph = osc->phase * AG_WT_SIZE;
    int i1 = (int)ph;
    float frac = (float)(ph - (double)i1);
    int i0 = (i1-1) & AG_WT_SIZE_MASK;
    int i2 = (i1+1) & AG_WT_SIZE_MASK;
    int i3 = (i1+2) & AG_WT_SIZE_MASK;
    float *tbl = osc->freq > osc->sr*0.12 ? osc->wt.table_hf : osc->wt.table;
    float y0=tbl[i0], y1=tbl[i1 & AG_WT_SIZE_MASK], y2=tbl[i2], y3=tbl[i3];
    float out = cubic_interp(y0,y1,y2,y3,frac);
    osc->phase += osc->freq / osc->sr;
    if (osc->phase >= 1.0) osc->phase -= 1.0;
    return out;
}

void ag_lfo_init(AgLFO *lfo, AgOscType type, double freq, double sr, float depth) {
    ag_osc_init(&lfo->osc, type, sr);
    ag_osc_set_freq(&lfo->osc, freq);
    lfo->depth = depth;
    lfo->offset = 0.0f;
    lfo->smooth=0.0f;
    lfo->last=0.0f;
}
float ag_lfo_next(AgLFO *lfo) {
    float v = ag_osc_next(&lfo->osc);
    return lfo->offset + v * lfo->depth;
}
float ag_lfo_next_smooth(AgLFO *lfo) {
    float v = ag_osc_next(&lfo->osc);
    float target = lfo->offset + v * lfo->depth;
    lfo->last = lfo->last*0.85f + target*0.15f;
    return lfo->last;
}

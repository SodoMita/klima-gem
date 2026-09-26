#include "ag_filter.h"
#include <math.h>
#include <string.h>

void ag_biquad_init(AgBiquad *f) {
    memset(f,0,sizeof(*f));
    f->b0=1.0f;
    f->b0_d=1.0;
}

void ag_biquad_set(AgBiquad *f, AgFilterType type, float freq, float q, float gain_db, float sr) {
    ag_biquad_set_hq(f,type,freq,q,gain_db,sr);
}

void ag_biquad_set_hq(AgBiquad *f, AgFilterType type, float freq, float q, float gain_db, float sr) {
    if (sr < 100) sr = 44100;
    if (freq < 1) freq = 1;
    if (freq > sr*0.495f) freq = sr*0.495f;
    if (q < 0.01f) q = 0.01f;
    f->freq=freq; f->q=q; f->gain_db=gain_db; f->type=type;
    double w0 = 2.0 * AG_PI * freq / sr;
    double cos_w0 = cos(w0);
    double sin_w0 = sin(w0);
    double alpha = sin_w0 / (2.0 * q);
    double A = pow(10.0, gain_db / 40.0);
    double b0=1,b1=0,b2=0,a0=1,a1=0,a2=0;
    switch (type) {
        case AG_FILTER_LP:
            b0 = (1 - cos_w0) * 0.5;
            b1 = 1 - cos_w0;
            b2 = b0;
            a0 = 1 + alpha;
            a1 = -2*cos_w0;
            a2 = 1 - alpha;
            break;
        case AG_FILTER_HP:
            b0 = (1 + cos_w0)*0.5;
            b1 = -(1 + cos_w0);
            b2 = b0;
            a0 = 1 + alpha;
            a1 = -2*cos_w0;
            a2 = 1 - alpha;
            break;
        case AG_FILTER_BP:
            b0 = sin_w0*0.5;
            b1 = 0;
            b2 = -sin_w0*0.5;
            a0 = 1 + alpha;
            a1 = -2*cos_w0;
            a2 = 1 - alpha;
            break;
        case AG_FILTER_NOTCH:
            b0 = 1;
            b1 = -2*cos_w0;
            b2 = 1;
            a0 = 1 + alpha;
            a1 = -2*cos_w0;
            a2 = 1 - alpha;
            break;
        case AG_FILTER_PEAK: {
            double alphaA = alpha * A;
            double alphaDiv = alpha / A;
            b0 = 1 + alphaA;
            b1 = -2*cos_w0;
            b2 = 1 - alphaA;
            a0 = 1 + alphaDiv;
            a1 = -2*cos_w0;
            a2 = 1 - alphaDiv;
        } break;
        case AG_FILTER_LOSHELF: {
            double S = q>0?q:1;
            double beta = sqrt(A)/S;
            b0 = A*((A+1)-(A-1)*cos_w0 + beta*sin_w0);
            b1 = 2*A*((A-1)-(A+1)*cos_w0);
            b2 = A*((A+1)-(A-1)*cos_w0 - beta*sin_w0);
            a0 = (A+1)+(A-1)*cos_w0 + beta*sin_w0;
            a1 = -2*((A-1)+(A+1)*cos_w0);
            a2 = (A+1)+(A-1)*cos_w0 - beta*sin_w0;
        } break;
        case AG_FILTER_HISHELF: {
            double S = q>0?q:1;
            double beta = sqrt(A)/S;
            b0 = A*((A+1)+(A-1)*cos_w0 + beta*sin_w0);
            b1 = -2*A*((A-1)+(A+1)*cos_w0);
            b2 = A*((A+1)+(A-1)*cos_w0 - beta*sin_w0);
            a0 = (A+1)-(A-1)*cos_w0 + beta*sin_w0;
            a1 = 2*((A-1)-(A+1)*cos_w0);
            a2 = (A+1)-(A-1)*cos_w0 - beta*sin_w0;
        } break;
        case AG_FILTER_LP_1POLE:
        case AG_FILTER_HP_1POLE:
        default:
            b0=1; b1=0; b2=0; a0=1; a1=0; a2=0;
            break;
    }
    f->b0_d = b0 / a0;
    f->b1_d = b1 / a0;
    f->b2_d = b2 / a0;
    f->a1_d = a1 / a0;
    f->a2_d = a2 / a0;
    f->b0 = (float)f->b0_d;
    f->b1 = (float)f->b1_d;
    f->b2 = (float)f->b2_d;
    f->a1 = (float)f->a1_d;
    f->a2 = (float)f->a2_d;
}

float ag_biquad_process(AgBiquad *f, float in) {
    return ag_biquad_process_hq(f,in);
}
float ag_biquad_process_hq(AgBiquad *f, float in) {
    /* Transposed Direct Form II for better numerical stability */
    double out = f->b0_d*in + f->z1;
    f->z1 = f->b1_d*in - f->a1_d*out + f->z2;
    f->z2 = f->b2_d*in - f->a2_d*out;
    /* denormal protection */
    if(fabs(f->z1)<1e-30) f->z1=0;
    if(fabs(f->z2)<1e-30) f->z2=0;
    return (float)out;
}
void ag_biquad_process_block(AgBiquad *f, float *buf, int n) {
    for (int i=0;i<n;i++) buf[i]=ag_biquad_process_hq(f, buf[i]);
}
void ag_biquad_process_block_hq(AgBiquad *f, float *buf, int n) {
    ag_biquad_process_block(f,buf,n);
}

/* One pole HQ */
void ag_onepole_lp(AgOnePole *f, float freq, float sr) { ag_onepole_lp_hq(f,freq,sr); }
void ag_onepole_hp(AgOnePole *f, float freq, float sr) {
    float x = expf(-2.0f * (float)AG_PI * freq / sr);
    f->b1 = x;
    f->a0 = 1.0f - x;
    f->z1 = 0.0f;
    f->freq=freq;
}
void ag_onepole_lp_hq(AgOnePole *f, float freq, float sr) {
    if(freq<1) freq=1;
    if(freq>sr*0.49f) freq=sr*0.49f;
    float g = tanf((float)AG_PI * freq / sr);
    float a = g / (1.0f + g);
    f->a0 = a;
    f->b1 = 1.0f - a;
    f->z1 = 0.0f;
    f->freq=freq;
}
float ag_onepole_process(AgOnePole *f, float in) { return ag_onepole_process_hq(f,in); }
float ag_onepole_process_hq(AgOnePole *f, float in) {
    float out = f->a0*in + f->b1*f->z1;
    f->z1 = out;
    if(fabsf(f->z1)<1e-30f) f->z1=0;
    return out;
}

/* SVF ZDF */
void ag_svf_init(AgSVF *svf, float freq, float q, float sr) {
    memset(svf,0,sizeof(*svf));
    svf->sr = sr;
    ag_svf_set_hq(svf,freq,q,sr);
}
void ag_svf_set(AgSVF *svf, float freq, float q) { ag_svf_set_hq(svf,freq,q,svf->sr); }
void ag_svf_set_hq(AgSVF *svf, float freq, float q, float sr) {
    if(sr>100) svf->sr=sr;
    svf->freq = ag_clamp_f(freq, 5.0f, sr*0.49f);
    svf->q = q < 0.1f ? 0.1f : q;
    if(svf->q>20) svf->q=20;
    svf->g = tanf((float)AG_PI * svf->freq / svf->sr);
    svf->k = 1.0f / svf->q;
    svf->a1 = 1.0f / (1.0f + svf->g*(svf->g+svf->k));
    svf->a2 = svf->g*svf->a1;
    svf->a3 = svf->g*svf->a2;
}
void ag_svf_process(AgSVF *svf, float in, float *lp, float *hp, float *bp, float *notch) {
    ag_svf_process_hq(svf,in,lp,hp,bp,notch,NULL);
}
void ag_svf_process_hq(AgSVF *svf, float in, float *lp, float *hp, float *bp, float *notch, float *peak) {
    float v3 = in - svf->ic2eq;
    float v1 = svf->a1*svf->ic1eq + svf->a2*v3;
    float v2 = svf->ic2eq + svf->a2*svf->ic1eq + svf->a3*v3;
    svf->ic1eq = 2*v1 - svf->ic1eq;
    svf->ic2eq = 2*v2 - svf->ic2eq;
    if(fabsf(svf->ic1eq)<1e-30f) svf->ic1eq=0;
    if(fabsf(svf->ic2eq)<1e-30f) svf->ic2eq=0;
    if (lp) *lp = v2;
    if (bp) *bp = v1;
    if (hp) *hp = in - svf->k*v1 - v2;
    if (notch) *notch = in - svf->k*v1;
    if (peak) *peak = v2 - v1*svf->k*0.5f;
}

/* DC blocker HQ */
void ag_dcblock_init(AgDCBlock *f) { f->x1=0; f->y1=0; f->r=0.995f; }
void ag_dcblock_set(AgDCBlock *f, float cutoff, float sr) {
    if(cutoff<1) cutoff=5;
    f->r = expf(-2.0f*(float)AG_PI*cutoff/sr);
}
float ag_dcblock_process(AgDCBlock *f, float in) {
    float y = in - f->x1 + f->r * f->y1;
    f->x1 = in;
    f->y1 = y;
    if(fabsf(f->y1)<1e-30f) f->y1=0;
    return y;
}

/* Ladder ZDF */
void ag_ladder_init(AgLadder *f, float freq, float res, float sr) {
    memset(f,0,sizeof(*f));
    f->sr = sr;
    ag_ladder_set_hq(f,freq,res,sr);
}
void ag_ladder_set(AgLadder *f, float freq, float res) { ag_ladder_set_hq(f,freq,res,f->sr); }
void ag_ladder_set_hq(AgLadder *f, float freq, float res, float sr) {
    if(sr>100) f->sr=sr;
    f->freq = ag_clamp_f(freq, 10, sr*0.45f);
    f->res = ag_clamp_f(res, 0.0f, 0.995f);
    f->k = f->res * 4.0f;
    f->acr = (float)AG_PI * f->freq / f->sr;
    if(f->acr>1.0f) f->acr=1.0f;
}
float ag_ladder_process(AgLadder *f, float in) { return ag_ladder_process_hq(f,in); }
float ag_ladder_process_hq(AgLadder *f, float in) {
    /* 1-pole per stage with tanh saturation and zero-delay feedback */
    float g = f->acr;
    /* compute feedback with acr compensation */
    float fb = f->k;
    float input = in - fb * f->stage[3];
    /* 4 stages */
    for (int i=0;i<4;i++) {
        float stage_in = (i==0)? input : f->stage[i-1];
        /* nonlinear */
        float new_stage = f->stage[i] + g * (tanhf(stage_in) - tanhf(f->stage[i]));
        f->stage[i] = new_stage;
        if(fabsf(f->stage[i])<1e-30f) f->stage[i]=0;
    }
    return f->stage[3];
}
float ag_ladder_process_oversampled(AgLadder *f, float in) {
    /* 2x oversample */
    float g = f->acr * 0.5f; /* half for oversample */
    float fb = f->k;
    float out=0;
    for(int os=0;os<2;os++){
        float input = (os==0?in:(in+f->oversample_buf[0])*0.5f) - fb * f->stage[3];
        for(int i=0;i<4;i++){
            float stage_in = (i==0)? input : f->stage[i-1];
            float new_stage = f->stage[i] + g * (tanhf(stage_in) - tanhf(f->stage[i]));
            f->stage[i]=new_stage;
        }
        f->oversample_buf[os]=f->stage[3];
        out=f->stage[3];
    }
    return (f->oversample_buf[0]+out)*0.5f;
}

/* Cascade */
void ag_cascade_init(AgFilterCascade *c) { memset(c,0,sizeof(*c)); c->stages=1; }
void ag_cascade_set_lp(AgFilterCascade *c, float freq, float q, float sr, int stages) {
    if(stages<1) stages=1;
    if(stages>4) stages=4;
    c->stages=stages;
    for(int i=0;i<stages;i++){
        ag_biquad_init(&c->bq[i]);
        /* stagger Q for Butterworth */
        float qi = q * (1.0f + i*0.1f);
        ag_biquad_set_hq(&c->bq[i], AG_FILTER_LP, freq, qi, 0, sr);
    }
}
float ag_cascade_process(AgFilterCascade *c, float in) {
    float out=in;
    for(int i=0;i<c->stages;i++) out=ag_biquad_process_hq(&c->bq[i], out);
    return out;
}

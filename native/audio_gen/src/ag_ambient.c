#include "ag_ambient.h"
#include "ag_filter.h"
#include <math.h>
#include <string.h>

void ag_drone_init(AgDrone *d, double sr, float base_freq) {
    memset(d,0,sizeof(*d));
    d->sr = sr>0?sr:AG_SR_DEFAULT;
    d->gain = 0.52f;
    d->detune = 0.018f;
    ag_osc_init(&d->osc1, AG_OSC_SINE, sr);
    ag_osc_init(&d->osc2, AG_OSC_SINE, sr);
    ag_osc_init(&d->osc3, AG_OSC_SINE, sr);
    ag_osc_init(&d->osc4, AG_OSC_SINE, sr);
    ag_osc_set_freq(&d->osc1, base_freq);
    ag_osc_set_freq(&d->osc2, base_freq*1.007);
    ag_osc_set_freq(&d->osc3, base_freq*0.993);
    ag_osc_set_freq(&d->osc4, base_freq*2.01);
    ag_biquad_init(&d->filter);
    ag_biquad_init(&d->filter2);
    ag_biquad_set(&d->filter, AG_FILTER_LP, base_freq*2.2f, 0.72f, 0, (float)sr);
    ag_biquad_set(&d->filter2, AG_FILTER_LP, base_freq*4.5f, 0.7f, 0, (float)sr);
    ag_lfo_init(&d->lfo, AG_OSC_SINE, 0.09, sr, 0.28f);
    ag_lfo_init(&d->lfo2, AG_OSC_SINE, 0.13, sr, 0.15f);
    ag_noise_init(&d->noise, 0xD10);
    ag_noise_init(&d->noise2, 0xD11);
    ag_dcblock_init(&d->dc);
}
void ag_drone_set_freq(AgDrone *d, float freq) {
    ag_osc_set_freq(&d->osc1, freq);
    ag_osc_set_freq(&d->osc2, freq*(1.0+d->detune));
    ag_osc_set_freq(&d->osc3, freq*(1.0-d->detune*0.6));
    ag_osc_set_freq(&d->osc4, freq*2.0*(1.0+d->detune*0.3));
    ag_biquad_set(&d->filter, AG_FILTER_LP, freq*2.8f, 0.72f, 0, (float)d->sr);
    ag_biquad_set(&d->filter2, AG_FILTER_LP, freq*5.0f, 0.7f, 0, (float)d->sr);
}
float ag_drone_next(AgDrone *d) {
    float s1 = ag_osc_next(&d->osc1);
    float s2 = ag_osc_next(&d->osc2);
    float s3 = ag_osc_next(&d->osc3);
    float s4 = ag_osc_next(&d->osc4) * 0.28f;
    float lfo = ag_lfo_next_smooth(&d->lfo);
    float lfo2 = ag_lfo_next_smooth(&d->lfo2);
    float mix = (s1*0.5f + s2*0.35f + s3*0.35f + s4*0.2f)/1.4f;
    mix += ag_noise_pink_hq(&d->noise) * 0.025f + ag_noise_brown(&d->noise2)*0.015f;
    mix = ag_biquad_process_hq(&d->filter, mix);
    mix = ag_biquad_process_hq(&d->filter2, mix);
    mix *= (1.0f + lfo*0.22f + lfo2*0.12f);
    mix = ag_dcblock_process(&d->dc, mix);
    mix = tanhf(mix*0.9f)*1.05f;
    return mix * d->gain;
}

/* Wind HQ */
void ag_wind_init(AgWindGen *w, double sr) {
    memset(w,0,sizeof(*w));
    w->sr = sr>0?sr:AG_SR_DEFAULT;
    w->gain = 0.52f;
    w->gust_strength = 0.32f;
    ag_noise_init(&w->noise, 0x111);
    ag_noise_init(&w->noise2, 0x112);
    ag_biquad_init(&w->lp1); ag_biquad_set(&w->lp1, AG_FILTER_LP, 850.0f, 0.68f, 0, (float)sr);
    ag_biquad_init(&w->lp2); ag_biquad_set(&w->lp2, AG_FILTER_LP, 420.0f, 0.7f, 0, (float)sr);
    ag_biquad_init(&w->lp3); ag_biquad_set(&w->lp3, AG_FILTER_LP, 220.0f, 0.7f, 0, (float)sr);
    ag_onepole_lp_hq(&w->smooth, 1.8f, (float)sr);
    ag_lfo_init(&w->gust_lfo, AG_OSC_SINE, 0.14, sr, 1.0f);
    ag_lfo_init(&w->gust_lfo2, AG_OSC_SINE, 0.07, sr, 0.6f);
}
void ag_wind_set_strength(AgWindGen *w, float strength) {
    w->gust_strength = ag_clamp_f(strength, 0, 1);
}
float ag_wind_next(AgWindGen *w) {
    float white = ag_noise_white(&w->noise);
    float pink = ag_noise_pink_hq(&w->noise);
    float brown = ag_noise_brown(&w->noise2)*0.5f;
    float n = white*0.25f + pink*0.55f + brown*0.2f;
    n = ag_biquad_process_hq(&w->lp1, n);
    n = ag_biquad_process_hq(&w->lp2, n);
    n = ag_biquad_process_hq(&w->lp3, n*0.6f + n*0.4f);
    float gust = ag_lfo_next_smooth(&w->gust_lfo) * w->gust_strength;
    float gust2 = ag_lfo_next_smooth(&w->gust_lfo2) * w->gust_strength*0.5f;
    float env = 0.48f + gust*0.5f + gust2*0.25f;
    env = ag_onepole_process_hq(&w->smooth, env);
    return n * env * w->gain;
}

/* Rain HQ */
void ag_rain_init(AgRain *r, double sr) {
    memset(r,0,sizeof(*r));
    r->sr = sr>0?sr:AG_SR_DEFAULT;
    r->gain = 0.42f;
    r->density = 0.32f;
    ag_noise_init(&r->noise, 0xA11A);
    ag_noise_init(&r->noise2, 0xA11B);
    ag_rng_seed(&r->rng, 0xA11A);
    ag_biquad_init(&r->bp); ag_biquad_set(&r->bp, AG_FILTER_BP, 2600.0f, 1.6f, 0, (float)sr);
    ag_biquad_init(&r->bp2);ag_biquad_set(&r->bp2,AG_FILTER_BP,4800.0f,1.2f,0,(float)sr);
    ag_biquad_init(&r->lp); ag_biquad_set(&r->lp, AG_FILTER_LP, 4000.0f,0.7f,0,(float)sr);
}
void ag_rain_set_density(AgRain *r, float density) { r->density = ag_clamp_f(density,0,1); }
float ag_rain_next(AgRain *r) {
    r->timer += 1.0/r->sr;
    float out = 0.0f;
    if (ag_rng_next_f32(&r->rng) < r->density * 0.12f) {
        float drop = ag_rng_range_f32(&r->rng, 0.25f, 1.0f);
        float freq = ag_rng_range_f32(&r->rng, 1600.0f, 6200.0f);
        ag_biquad_set(&r->bp, AG_FILTER_BP, freq, 1.8f + ag_rng_next_f32(&r->rng)*0.5f, 0, (float)r->sr);
        ag_biquad_set(&r->bp2, AG_FILTER_BP, freq*1.8f, 1.2f, 0, (float)r->sr);
        float n = ag_noise_white(&r->noise) * drop;
        n = ag_biquad_process_hq(&r->bp, n);
        float n2 = ag_biquad_process_hq(&r->bp2, n*0.5f);
        out += (n*0.75f + n2*0.35f) * 0.85f;
    }
    float drizzle = ag_noise_white(&r->noise)*0.04f + ag_noise_pink_hq(&r->noise2)*0.03f;
    drizzle = ag_biquad_process_hq(&r->lp, drizzle);
    drizzle = ag_biquad_process_hq(&r->bp, drizzle*0.3f) * 0.2f + drizzle*0.8f;
    out += drizzle;
    return out * r->gain;
}

/* Granular HQ */
void ag_granular_init(AgGranularPad *gp, double sr, float base_freq) {
    memset(gp,0,sizeof(*gp));
    gp->sr = sr>0?sr:AG_SR_DEFAULT;
    gp->base_freq = base_freq>0?base_freq:110.0f;
    gp->spread = 0.12f;
    gp->grain_rate = 22.0f;
    gp->gain = 0.62f;
    ag_rng_seed(&gp->rng, 0x611A);
    ag_biquad_init(&gp->filter); ag_biquad_set(&gp->filter, AG_FILTER_LP, base_freq*4.2f, 0.72f, 0, (float)sr);
    ag_biquad_init(&gp->filter2);ag_biquad_set(&gp->filter2,AG_FILTER_LP, base_freq*6.0f,0.7f,0,(float)sr);
    for (int i=0;i<AG_GRAIN_MAX;i++) gp->grains[i].active=0;
    ag_lfo_init(&gp->lfo, AG_OSC_SINE, 0.11f, sr, 0.15f);
}
void ag_granular_set(AgGranularPad *gp, float freq, float spread, float rate) {
    gp->base_freq = freq;
    gp->spread = spread;
    gp->grain_rate = rate;
    ag_biquad_set(&gp->filter, AG_FILTER_LP, freq*4.5f, 0.72f, 0, (float)gp->sr);
    ag_biquad_set(&gp->filter2, AG_FILTER_LP, freq*7.0f, 0.7f, 0, (float)gp->sr);
}
static void spawn_grain(AgGranularPad *gp) {
    for (int i=0;i<AG_GRAIN_MAX;i++) {
        if (!gp->grains[i].active) {
            AgGrain *g = &gp->grains[i];
            float detune = ag_rng_range_f32(&gp->rng, -gp->spread, gp->spread);
            float freq = gp->base_freq * powf(2.0f, detune);
            int len = (int)(gp->sr / freq * 2.5);
            if (len < 64) len=64;
            if (len > AG_GRAIN_LEN) len=AG_GRAIN_LEN;
            g->len = len;
            g->pos = 0;
            g->env_phase = 0.0;
            float lfo = ag_lfo_next(&gp->lfo)*0.05f;
            for (int j=0;j<len;j++) {
                float ph = (float)j / len;
                float win = 0.5f - 0.5f*cosf(ph*AG_TAU); /* Hann */
                /* slightly detuned osc with second harmonic */
                float osc = sinf(ph * (float)AG_TAU * 2.0f * (1.0f+lfo));
                float osc2 = sinf(ph * (float)AG_TAU * 4.0f)*0.18f;
                g->buf[j] = (osc*0.85f + osc2*0.15f) * win;
            }
            float pan = ag_rng_range_f32(&gp->rng, -1.0f, 1.0f);
            ag_buffer_pan_stereo(1.0f, pan, &g->pan_l, &g->pan_r);
            g->gain = ag_rng_range_f32(&gp->rng, 0.28f, 0.82f);
            g->active=1;
            return;
        }
    }
}
float ag_granular_next(AgGranularPad *gp) {
    float l,r; ag_granular_next_stereo(gp,&l,&r); return (l+r)*0.5f;
}
void ag_granular_next_stereo(AgGranularPad *gp, float *out_l, float *out_r) {
    gp->timer += 1.0/gp->sr;
    double interval = 1.0 / (gp->grain_rate>0?gp->grain_rate:22.0);
    if (gp->timer >= interval) {
        gp->timer=0;
        spawn_grain(gp);
        if(ag_rng_next_f32(&gp->rng) < gp->grain_rate*0.02f) spawn_grain(gp); /* occasional double */
    }
    float mix_l=0, mix_r=0;
    for (int i=0;i<AG_GRAIN_MAX;i++) {
        AgGrain *g = &gp->grains[i];
        if (!g->active) continue;
        float s = g->buf[g->pos];
        mix_l += s * g->pan_l * g->gain;
        mix_r += s * g->pan_r * g->gain;
        g->pos++;
        if (g->pos >= g->len) g->active=0;
    }
    mix_l = ag_biquad_process_hq(&gp->filter, mix_l);
    mix_l = ag_biquad_process_hq(&gp->filter2, mix_l*0.7f + mix_l*0.3f);
    mix_r = ag_biquad_process_hq(&gp->filter, mix_r);
    mix_r = ag_biquad_process_hq(&gp->filter2, mix_r);
    *out_l = mix_l * gp->gain;
    *out_r = mix_r * gp->gain;
}

/* Shimmer HQ - pitch shifted delay */
void ag_shimmer_init(AgShimmer *sh, double sr, float base_freq) {
    memset(sh,0,sizeof(*sh));
    sh->sr = sr>0?sr:AG_SR_DEFAULT;
    sh->gain=0.52f;
    sh->feedback=0.62f;
    sh->shift=2.0f;
    ag_osc_init(&sh->osc, AG_OSC_SINE, sr);
    ag_osc_set_freq(&sh->osc, base_freq*2.0);
    ag_biquad_init(&sh->filter); ag_biquad_set(&sh->filter, AG_FILTER_LP, 3200.0f, 0.72f, 0, (float)sr);
    ag_biquad_init(&sh->filter2);ag_biquad_set(&sh->filter2,AG_FILTER_HP, 120.0f,0.7f,0,(float)sr);
    sh->buf_pos=0;
    sh->read_pos=0;
}
float ag_shimmer_next(AgShimmer *sh, float in) {
    /* simple pitch shift via 2x read speed */
    float delayed = sh->buf[sh->buf_pos];
    float lfo = ag_osc_next(&sh->osc) * 0.08f;
    float out = in + delayed * sh->feedback * (0.9f + lfo);
    out = ag_biquad_process_hq(&sh->filter, out);
    out = ag_biquad_process_hq(&sh->filter2, out);
    /* write */
    sh->buf[sh->buf_pos] = out * 0.85f + in*0.15f;
    sh->buf_pos = (sh->buf_pos+1) % 44100;
    /* read with shift */
    sh->read_pos += sh->shift;
    if(sh->read_pos>=44100) sh->read_pos-=44100;
    int rp = (int)sh->read_pos;
    float frac = sh->read_pos - rp;
    int rp2 = (rp+1)%44100;
    float pitch_shifted = sh->buf[rp]*(1.0f-frac) + sh->buf[rp2]*frac;
    return (out*0.6f + pitch_shifted*0.4f) * sh->gain;
}

/* Underwater HQ */
void ag_underwater_init(AgUnderwater *uw, double sr) {
    memset(uw,0,sizeof(*uw));
    uw->sr = sr>0?sr:AG_SR_DEFAULT;
    uw->gain=1.0f;
    ag_biquad_init(&uw->lp); ag_biquad_set(&uw->lp, AG_FILTER_LP, 850.0f, 0.82f, 0, (float)sr);
    ag_biquad_init(&uw->lp2);ag_biquad_set(&uw->lp2,AG_FILTER_LP,400.0f,0.7f,0,(float)sr);
    ag_biquad_init(&uw->hp); ag_biquad_set(&uw->hp, AG_FILTER_HP, 22.0f, 0.7f, 0, (float)sr);
    ag_osc_init(&uw->lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&uw->lfo, 0.28);
    ag_osc_init(&uw->lfo2, AG_OSC_SINE, sr); ag_osc_set_freq(&uw->lfo2, 0.07);
    ag_dcblock_init(&uw->dc);
}
float ag_underwater_process(AgUnderwater *uw, float in) {
    float lfo = ag_osc_next(&uw->lfo) * 0.22f;
    float lfo2 = ag_osc_next(&uw->lfo2) * 0.12f;
    float fc = 620.0f + lfo*220.0f + lfo2*80.0f;
    ag_biquad_set(&uw->lp, AG_FILTER_LP, fc, 0.82f, 0, (float)uw->sr);
    ag_biquad_set(&uw->lp2, AG_FILTER_LP, fc*0.55f, 0.7f, 0, (float)uw->sr);
    float out = ag_biquad_process_hq(&uw->lp, in);
    out = ag_biquad_process_hq(&uw->lp2, out);
    out = ag_biquad_process_hq(&uw->hp, out);
    out = ag_dcblock_process(&uw->dc, out);
    return out * uw->gain;
}

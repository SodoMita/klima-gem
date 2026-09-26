#include "ag_distortion.h"
#include <math.h>
#include <string.h>

void ag_dist_init(AgDistortion *d, float sr) {
    memset(d,0,sizeof(*d));
    d->sr = sr>0?sr:44100;
    d->drive=2.2f; d->mix=0.55f; d->tone=4200.0f;
    ag_biquad_init(&d->lp);
    ag_biquad_set(&d->lp, AG_FILTER_LP, d->tone, 0.7f, 0, d->sr);
    ag_biquad_init(&d->hp);
    ag_biquad_set(&d->hp, AG_FILTER_HP, 30.0f, 0.7f, 0, d->sr);
    ag_dcblock_init(&d->dc);
}
void ag_dist_set(AgDistortion *d, float drive, float mix, float tone) {
    d->drive=ag_clamp_f(drive,0.5f,30.0f);
    d->mix=ag_clamp_f(mix,0,1);
    d->tone=ag_clamp_f(tone,80,18000);
    ag_biquad_set(&d->lp, AG_FILTER_LP, d->tone, 0.72f, 0, d->sr);
}
float ag_dist_process(AgDistortion *d, float in) {
    /* 2x oversample */
    float out_acc=0;
    for(int os=0;os<2;os++){
        float driven = in * d->drive * (os==0?1.0f:0.92f);
        /* pre-emphasis */
        driven = ag_biquad_process(&d->hp, driven);
        /* soft clip with asymmetric for warmth */
        float distorted = tanhf(driven*0.9f)*1.05f;
        distorted += tanhf(driven*1.8f)*0.12f; /* add harmonics */
        distorted = ag_biquad_process(&d->lp, distorted);
        out_acc+=distorted;
    }
    float distorted = out_acc*0.5f;
    distorted = ag_dcblock_process(&d->dc, distorted);
    float out = in*(1.0f-d->mix) + distorted*d->mix;
    /* final soft clip */
    out = tanhf(out*0.95f)*1.02f;
    return out;
}

void ag_bitcrush_init(AgBitcrush *bc, float sr) {
    memset(bc,0,sizeof(*bc));
    bc->sr=sr>0?sr:44100;
    bc->bit_depth=8; bc->sample_rate_div=4;
    bc->hold_time = bc->sample_rate_div / bc->sr;
    ag_biquad_init(&bc->aa_lp);
    ag_biquad_set(&bc->aa_lp, AG_FILTER_LP, sr*0.45f, 0.7f, 0, sr);
}
void ag_bitcrush_set(AgBitcrush *bc, float bits, float sr_div) {
    bc->bit_depth=ag_clamp_f(bits,1,16);
    bc->sample_rate_div=ag_clamp_f(sr_div,1,200);
    bc->hold_time = bc->sample_rate_div / bc->sr;
    float cutoff = bc->sr / bc->sample_rate_div * 0.45f;
    if(cutoff> bc->sr*0.45f) cutoff=bc->sr*0.45f;
    ag_biquad_set(&bc->aa_lp, AG_FILTER_LP, cutoff, 0.7f, 0, bc->sr);
}
float ag_bitcrush_process(AgBitcrush *bc, float in) {
    bc->timer += 1.0/bc->sr;
    if(bc->timer >= bc->hold_time){
        bc->timer=0;
        float filtered = ag_biquad_process(&bc->aa_lp, in);
        float steps = powf(2.0f, bc->bit_depth);
        /* dither */
        float dither = ag_rng_range_f32(&bc->rng, -0.5f/steps, 0.5f/steps);
        bc->hold = floorf((filtered + dither) * steps) / steps;
        bc->last=filtered;
    }
    return bc->hold;
}

void ag_wavefolder_init(AgWavefolder *wf) {
    wf->threshold=1.0f; wf->gain=1.0f;
    wf->offset=0.0f;
    wf->smooth=0.0f;
}
float ag_wavefolder_process(AgWavefolder *wf, float in) {
    float x = in * wf->gain + wf->offset;
    float th = wf->threshold;
    /* HQ folding with smooth transitions */
    int folds=0;
    while(fabsf(x)>th && folds<8){
        if(x>th) x = th*2 - x;
        else if(x<-th) x = -th*2 - x;
        folds++;
    }
    /* soft fold edge */
    if(fabsf(x) > th*0.85f){
        float t = (fabsf(x)-th*0.85f)/(th*0.15f);
        t = t*t*(3-2*t);
        x = x*(1.0f - t*0.15f) + tanhf(x*1.2f)*0.15f*t;
    }
    float out = x;
    /* smooth */
    wf->smooth = wf->smooth*0.85f + out*0.15f;
    return wf->smooth*0.3f + out*0.7f;
}

void ag_comp_init(AgCompressor *c, float sr) {
    memset(c,0,sizeof(*c));
    c->sr=sr>0?sr:44100;
    c->threshold_db=-18; c->ratio=3.5f; c->attack_ms=12; c->release_ms=110; c->makeup_db=2.0f;
    c->knee_db=6.0f;
    ag_biquad_init(&c->sidechain_hp);
    ag_biquad_set(&c->sidechain_hp, AG_FILTER_HP, 80,0.7f,0,sr);
}
void ag_comp_set(AgCompressor *c, float thresh_db, float ratio, float attack_ms, float release_ms, float makeup_db) {
    c->threshold_db=thresh_db; c->ratio=ratio>1?ratio:1; c->attack_ms=attack_ms>0.1f?attack_ms:0.1f; c->release_ms=release_ms>1?release_ms:1; c->makeup_db=makeup_db;
}
float ag_comp_process(AgCompressor *c, float in) {
    float attack_coeff = expf(-1.0f / (c->attack_ms * 0.001f * c->sr));
    float release_coeff = expf(-1.0f / (c->release_ms * 0.001f * c->sr));
    float side = ag_biquad_process(&c->sidechain_hp, in);
    float abs_in = fabsf(side);
    /* peak with RMS blend */
    c->rms = c->rms*0.92f + abs_in*abs_in*0.08f;
    float rms = sqrtf(c->rms);
    float env_in = abs_in*0.6f + rms*0.4f;
    if(env_in > c->env) c->env = attack_coeff * c->env + (1-attack_coeff)*env_in;
    else c->env = release_coeff * c->env + (1-release_coeff)*env_in;
    float env_db = ag_lin_to_db(c->env + 1e-12f);
    float gain_db = 0;
    if(env_db > c->threshold_db){
        float excess = env_db - c->threshold_db;
        /* soft knee */
        if(excess < c->knee_db){
            excess = excess*excess / (c->knee_db*2.0f);
        } else {
            excess = excess - c->knee_db*0.5f;
        }
        gain_db = excess * (1.0f/c->ratio - 1.0f);
    }
    gain_db += c->makeup_db;
    float gain_lin = ag_db_to_lin(gain_db);
    /* smooth gain */
    c->gain_smooth = c->gain_smooth*0.92f + gain_lin*0.08f;
    return in * c->gain_smooth;
}

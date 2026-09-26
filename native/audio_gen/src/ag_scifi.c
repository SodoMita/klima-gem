#include "ag_scifi.h"
#include <string.h>
#include <math.h>

/* ---------- Laser HQ ---------- */
void ag_laser_init(AgLaser *l, double sr) {
    memset(l,0,sizeof(*l));
    l->sr=sr>0?sr:AG_SR_DEFAULT;
    l->gain=0.65f;
    ag_osc_init(&l->osc, AG_OSC_SAW, sr);
    ag_osc_init(&l->osc2, AG_OSC_SQUARE, sr);
    ag_biquad_init(&l->filter); ag_biquad_set(&l->filter, AG_FILTER_LP, 4200,0.72f,0,(float)sr);
    ag_biquad_init(&l->filter2); ag_biquad_set(&l->filter2, AG_FILTER_HP, 80,0.7f,0,(float)sr);
    AgADSR adsr={0.005f,0.18f,0.0f,0.12f,0.8f,1.2f,1.0f,0,0};
    ag_env_init(&l->env, adsr, sr);
    ag_dcblock_init(&l->dc);
    ag_rng_seed(&l->rng, 0x1A5E1);
}
void ag_laser_trigger(AgLaser *l, float start_freq, float end_freq, float duration, float vel) {
    if(start_freq<20) start_freq=20;
    if(end_freq<20) end_freq=20;
    if(duration<0.02f) duration=0.02f;
    l->start_freq=start_freq;
    l->end_freq=end_freq;
    l->duration=duration;
    AgADSR adsr={0.004f,duration*0.6f,0.0f,duration*0.35f,0.6f,1.2f,1.0f,0,0};
    ag_env_init(&l->env, adsr, l->sr);
    ag_env_trigger_vel(&l->env, vel);
    l->active=1; l->t=0;
    ag_osc_set_freq(&l->osc, start_freq);
    ag_osc_set_freq(&l->osc2, start_freq*1.01f);
}
float ag_laser_next(AgLaser *l) {
    if(!l->active) return 0.0f;
    l->t+=1.0/l->sr;
    float env=ag_env_next_hq(&l->env);
    if(ag_env_is_idle(&l->env)){ l->active=0; return 0.0f; }
    float prog=(float)(l->t / l->duration);
    if(prog>1) prog=1;
    /* exponential slide */
    float freq = l->start_freq * powf(l->end_freq/l->start_freq, prog);
    ag_osc_set_freq(&l->osc, freq);
    ag_osc_set_freq(&l->osc2, freq*1.005f);
    float s1=ag_osc_next_hq(&l->osc);
    float s2=ag_osc_next_hq(&l->osc2)*0.5f;
    float out=(s1*0.7f + s2*0.3f) * env;
    float cutoff = 3000 + freq*0.8f;
    if(cutoff>12000) cutoff=12000;
    ag_biquad_set(&l->filter, AG_FILTER_LP, cutoff,0.72f,0,(float)l->sr);
    out=ag_biquad_process_hq(&l->filter, out);
    out=ag_biquad_process_hq(&l->filter2, out);
    out=ag_dcblock_process(&l->dc, out);
    out=tanhf(out*0.9f)*1.05f;
    return out*l->gain;
}
int ag_laser_active(const AgLaser *l){ return l->active; }

/* ---------- Plasma HQ ---------- */
void ag_plasma_init(AgPlasma *p, double sr) {
    memset(p,0,sizeof(*p));
    p->sr=sr>0?sr:AG_SR_DEFAULT;
    p->gain=0.62f;
    ag_osc_init(&p->carrier, AG_OSC_SINE, sr);
    ag_osc_init(&p->mod, AG_OSC_SINE, sr);
    ag_osc_init(&p->mod2, AG_OSC_SINE, sr);
    ag_biquad_init(&p->bp); ag_biquad_set(&p->bp, AG_FILTER_BP, 1200,1.2f,0,(float)sr);
    ag_biquad_init(&p->lp); ag_biquad_set(&p->lp, AG_FILTER_LP, 4200,0.72f,0,(float)sr);
    AgADSR adsr={0.02f,0.4f,0.0f,0.3f,0.5f,1.2f,1.0f,0,0};
    ag_env_init(&p->env, adsr, sr);
    ag_dcblock_init(&p->dc);
    ag_rng_seed(&p->rng, 0x51A);
}
void ag_plasma_trigger(AgPlasma *p, float base_freq, float intensity, float duration) {
    if(base_freq<20) base_freq=20;
    ag_osc_set_freq(&p->carrier, base_freq);
    ag_osc_set_freq(&p->mod, base_freq*1.5f);
    ag_osc_set_freq(&p->mod2, base_freq*0.5f);
    AgADSR adsr={0.02f,duration*0.5f,0.0f,duration*0.4f,0.5f,1.2f,1.0f,0,0};
    ag_env_init(&p->env, adsr, p->sr);
    ag_env_trigger_vel(&p->env, intensity);
    p->active=1; p->t=0;
}
float ag_plasma_next(AgPlasma *p) {
    if(!p->active) return 0.0f;
    p->t+=1.0/p->sr;
    float env=ag_env_next_hq(&p->env);
    if(ag_env_is_idle(&p->env)){ p->active=0; return 0.0f; }
    float mod=ag_osc_next_hq(&p->mod)*0.8f + ag_osc_next_hq(&p->mod2)*0.4f;
    float phase_mod = mod * 2.5f * env;
    /* FM: carrier phase += mod */
    p->carrier.phase += phase_mod * 0.01f;
    if(p->carrier.phase>=1.0) p->carrier.phase-=1.0;
    if(p->carrier.phase<0) p->carrier.phase+=1.0;
    float s=ag_osc_next_hq(&p->carrier);
    s=ag_biquad_process_hq(&p->bp, s);
    s=ag_biquad_process_hq(&p->lp, s);
    s=ag_dcblock_process(&p->dc, s);
    s=tanhf(s*0.9f)*1.08f;
    return s*env*p->gain;
}
int ag_plasma_active(const AgPlasma *p){ return p->active; }

/* ---------- Warp HQ ---------- */
void ag_warp_init(AgWarp *w, double sr) {
    memset(w,0,sizeof(*w));
    w->sr=sr>0?sr:AG_SR_DEFAULT;
    w->gain=0.6f;
    w->depth=0.7f;
    ag_osc_init(&w->osc, AG_OSC_SAW, sr);
    ag_osc_init(&w->lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&w->lfo, 0.8f);
    ag_osc_init(&w->lfo2, AG_OSC_SINE, sr); ag_osc_set_freq(&w->lfo2, 2.3f); w->lfo2.phase=0.3f;
    ag_biquad_init(&w->lp); ag_biquad_set(&w->lp, AG_FILTER_LP, 3200,0.72f,0,(float)sr);
    ag_biquad_init(&w->hp); ag_biquad_set(&w->hp, AG_FILTER_HP, 80,0.7f,0,(float)sr);
    ag_biquad_init(&w->bp); ag_biquad_set(&w->bp, AG_FILTER_BP, 800,1.0f,0,(float)sr);
    AgADSR adsr={0.2f,0.6f,0.0f,0.8f,0.5f,1.2f,1.0f,0,0};
    ag_env_init(&w->env, adsr, sr);
    ag_dcblock_init(&w->dc);
}
void ag_warp_trigger(AgWarp *w, float duration, float depth, float vel) {
    depth=ag_clamp_f(depth,0,1);
    w->depth=depth;
    AgADSR adsr={duration*0.15f,duration*0.5f,0.0f,duration*0.35f,0.5f,1.2f,1.0f,0,0};
    ag_env_init(&w->env, adsr, w->sr);
    ag_env_trigger_vel(&w->env, vel);
    w->active=1; w->t=0;
    ag_osc_set_freq(&w->osc, 80 + depth*200);
}
float ag_warp_next(AgWarp *w) {
    if(!w->active) return 0.0f;
    w->t+=1.0/w->sr;
    float env=ag_env_next_hq(&w->env);
    if(ag_env_is_idle(&w->env)){ w->active=0; return 0.0f; }
    float lfo=ag_osc_next(&w->lfo)*w->depth*0.5f;
    float lfo2=ag_osc_next(&w->lfo2)*w->depth*0.25f;
    float freq = (80 + w->depth*200) * powf(2.0f, (lfo+lfo2)*1.5f) * (1.0f + env*0.5f);
    ag_osc_set_freq(&w->osc, freq);
    float s=ag_osc_next_hq(&w->osc);
    float fc = 600 + env*2400 + w->depth*1200;
    ag_biquad_set(&w->bp, AG_FILTER_BP, fc, 0.9f+w->depth*0.6f,0,(float)w->sr);
    s=ag_biquad_process_hq(&w->bp, s);
    s=ag_biquad_process_hq(&w->lp, s);
    s=ag_biquad_process_hq(&w->hp, s);
    s=ag_dcblock_process(&w->dc, s);
    s=tanhf(s*0.85f)*1.1f;
    return s*env*w->gain;
}
int ag_warp_active(const AgWarp *w){ return w->active; }

/* ---------- Scifi Drone HQ ---------- */
void ag_scifi_drone_init(AgScifiDrone *d, double sr, float base_freq) {
    memset(d,0,sizeof(*d));
    d->sr=sr>0?sr:AG_SR_DEFAULT;
    d->gain=0.52f;
    d->detune=0.018f;
    d->shimmer=0.25f;
    ag_osc_init(&d->osc1, AG_OSC_SAW, sr); ag_osc_set_freq(&d->osc1, base_freq);
    ag_osc_init(&d->osc2, AG_OSC_SAW, sr); ag_osc_set_freq(&d->osc2, base_freq*1.007f);
    ag_osc_init(&d->osc3, AG_OSC_SINE, sr); ag_osc_set_freq(&d->osc3, base_freq*0.5f);
    ag_osc_init(&d->osc4, AG_OSC_SINE, sr); ag_osc_set_freq(&d->osc4, base_freq*2.01f);
    ag_biquad_init(&d->filter); ag_biquad_set(&d->filter, AG_FILTER_LP, base_freq*2.5f,0.72f,0,(float)sr);
    ag_biquad_init(&d->filter2); ag_biquad_set(&d->filter2, AG_FILTER_LP, base_freq*4.5f,0.7f,0,(float)sr);
    ag_biquad_init(&d->notch); ag_biquad_set(&d->notch, AG_FILTER_NOTCH, base_freq*1.5f,1.2f,0,(float)sr);
    ag_lfo_init(&d->lfo, AG_OSC_SINE, 0.09, sr, 0.28f);
    ag_lfo_init(&d->lfo2, AG_OSC_SINE, 0.13, sr, 0.18f);
    ag_noise_init(&d->noise, 0xD10);
    ag_dcblock_init(&d->dc);
}
void ag_scifi_drone_set_freq(AgScifiDrone *d, float freq) {
    ag_osc_set_freq(&d->osc1, freq);
    ag_osc_set_freq(&d->osc2, freq*(1.0+d->detune));
    ag_osc_set_freq(&d->osc3, freq*0.5f);
    ag_osc_set_freq(&d->osc4, freq*2.01f);
    ag_biquad_set(&d->filter, AG_FILTER_LP, freq*2.8f,0.72f,0,(float)d->sr);
    ag_biquad_set(&d->filter2, AG_FILTER_LP, freq*5.0f,0.7f,0,(float)d->sr);
    ag_biquad_set(&d->notch, AG_FILTER_NOTCH, freq*1.5f,1.2f,0,(float)d->sr);
}
float ag_scifi_drone_next(AgScifiDrone *d) {
    float l,r; ag_scifi_drone_next_stereo(d,&l,&r); return (l+r)*0.5f;
}
void ag_scifi_drone_next_stereo(AgScifiDrone *d, float *l, float *r) {
    float s1=ag_osc_next_hq(&d->osc1);
    float s2=ag_osc_next_hq(&d->osc2);
    float s3=ag_osc_next_hq(&d->osc3)*0.5f;
    float s4=ag_osc_next_hq(&d->osc4)*0.22f;
    float lfo=ag_lfo_next_smooth(&d->lfo);
    float lfo2=ag_lfo_next_smooth(&d->lfo2);
    float mix=(s1*0.5f + s2*0.35f + s3*0.4f + s4*0.25f)/1.5f;
    mix+=ag_noise_pink(&d->noise)*0.02f;
    mix=ag_biquad_process_hq(&d->filter, mix);
    mix=ag_biquad_process_hq(&d->filter2, mix);
    mix=ag_biquad_process_hq(&d->notch, mix);
    mix*=(1.0f + lfo*0.22f + lfo2*0.12f);
    mix=ag_dcblock_process(&d->dc, mix);
    mix=tanhf(mix*0.88f)*1.06f;
    mix*=d->gain;
    /* shimmer */
    float shim = mix * d->shimmer * 0.5f;
    *l=mix*0.6f + shim*0.4f;
    *r=mix*0.4f + shim*0.6f;
}

/* ---------- Force Field ---------- */
void ag_forcefield_init(AgForceField *ff, double sr, float base_freq) {
    memset(ff,0,sizeof(*ff));
    ff->sr=sr>0?sr:AG_SR_DEFAULT;
    ff->gain=0.52f;
    ff->buzz=0.35f;
    ag_osc_init(&ff->osc1, AG_OSC_SINE, sr); ag_osc_set_freq(&ff->osc1, base_freq);
    ag_osc_init(&ff->osc2, AG_OSC_SINE, sr); ag_osc_set_freq(&ff->osc2, base_freq*1.5f);
    ag_biquad_init(&ff->bp1); ag_biquad_set(&ff->bp1, AG_FILTER_BP, base_freq,1.2f,0,(float)sr);
    ag_biquad_init(&ff->bp2); ag_biquad_set(&ff->bp2, AG_FILTER_BP, base_freq*1.5f,1.0f,0,(float)sr);
    ag_biquad_init(&ff->lp); ag_biquad_set(&ff->lp, AG_FILTER_LP, base_freq*3.0f,0.72f,0,(float)sr);
    ag_lfo_init(&ff->lfo, AG_OSC_SINE, 4.5, sr, 0.15f);
    ag_lfo_init(&ff->lfo2, AG_OSC_SINE, 7.2, sr, 0.08f);
    ag_noise_init(&ff->noise, 0xF1E1D);
    ag_dcblock_init(&ff->dc);
}
float ag_forcefield_next(AgForceField *ff) {
    float l,r; ag_forcefield_next_stereo(ff,&l,&r); return (l+r)*0.5f;
}
void ag_forcefield_next_stereo(AgForceField *ff, float *l, float *r) {
    float lfo=ag_lfo_next_smooth(&ff->lfo);
    float lfo2=ag_lfo_next_smooth(&ff->lfo2);
    float s1=ag_osc_next_hq(&ff->osc1);
    float s2=ag_osc_next_hq(&ff->osc2)*0.6f;
    float buzz = ag_noise_pink(&ff->noise)*0.08f*ff->buzz;
    float mix=s1*0.5f + s2*0.35f + buzz;
    mix=ag_biquad_process_hq(&ff->bp1, mix);
    float mix2=ag_biquad_process_hq(&ff->bp2, mix*0.5f);
    mix=mix*0.7f + mix2*0.3f;
    mix*=(1.0f + lfo*0.18f + lfo2*0.08f);
    mix=ag_biquad_process_hq(&ff->lp, mix);
    mix=ag_dcblock_process(&ff->dc, mix);
    mix=tanhf(mix*0.9f)*1.05f;
    mix*=ff->gain;
    *l=mix*0.55f; *r=mix*0.45f;
}

/* ---------- Glitch ---------- */
void ag_glitch_init(AgGlitch *g, double sr) {
    memset(g,0,sizeof(*g));
    g->sr=sr>0?sr:AG_SR_DEFAULT;
    g->gain=0.6f;
    ag_noise_init(&g->noise, 0x61A);
    ag_biquad_init(&g->bp); ag_biquad_set(&g->bp, AG_FILTER_BP, 1800,1.2f,0,(float)sr);
    ag_biquad_init(&g->hp); ag_biquad_set(&g->hp, AG_FILTER_HP, 120,0.7f,0,(float)sr);
    ag_rng_seed(&g->rng, 0x61A);
    AgADSR adsr={0.001f,0.08f,0.0f,0.05f,0.8f,1.2f,1.0f,0,0};
    ag_env_init(&g->env, adsr, sr);
    ag_osc_init(&g->stutter_lfo, AG_OSC_SQUARE, sr); ag_osc_set_freq(&g->stutter_lfo, 12.0f);
    g->next_glitch=0.15;
    ag_dcblock_init(&g->dc);
}
void ag_glitch_trigger(AgGlitch *g, float intensity) {
    intensity=ag_clamp_f(intensity,0,1);
    float dur=0.02f + intensity*0.12f;
    AgADSR adsr={0.001f,dur*0.6f,0.0f,dur*0.4f,0.8f,1.2f,1.0f,0,0};
    ag_env_init(&g->env, adsr, g->sr);
    ag_env_trigger_vel(&g->env, intensity);
    g->active=1;
    /* fill buffer with noise */
    for(int i=0;i<1024;i++) g->buf[i]=ag_noise_white(&g->noise)*ag_rng_range_f32(&g->rng,0.2f,1.0f);
    g->buf_pos=0;
    ag_biquad_set(&g->bp, AG_FILTER_BP, ag_rng_range_f32(&g->rng,600,4200),1.0f+intensity,0,(float)g->sr);
    ag_osc_set_freq(&g->stutter_lfo, ag_rng_range_f32(&g->rng,6,32));
}
float ag_glitch_next(AgGlitch *g) {
    float l,r; ag_glitch_next_stereo(g,&l,&r); return (l+r)*0.5f;
}
void ag_glitch_next_stereo(AgGlitch *g, float *l, float *r) {
    g->timer+=1.0/g->sr;
    if(g->timer>=g->next_glitch){
        g->timer=0;
        g->next_glitch=ag_rng_range_f32(&g->rng,0.08f,0.45f);
        if(ag_rng_next_f32(&g->rng)<0.35f) ag_glitch_trigger(g, ag_rng_range_f32(&g->rng,0.3f,0.9f));
    }
    float out=0;
    if(g->active){
        float env=ag_env_next_hq(&g->env);
        if(ag_env_is_idle(&g->env)) g->active=0;
        else {
            float stutter=ag_osc_next(&g->stutter_lfo)>0?1.0f:0.15f;
            float s=g->buf[g->buf_pos];
            g->buf_pos=(g->buf_pos+1)%1024;
            s=ag_biquad_process_hq(&g->bp, s);
            s=ag_biquad_process_hq(&g->hp, s);
            out=s*env*stutter;
        }
    }
    out=ag_dcblock_process(&g->dc, out);
    out=tanhf(out*0.9f)*1.05f;
    *l=out*g->gain*0.6f;
    *r=out*g->gain*0.4f;
}

/* ---------- Hologram ---------- */
void ag_hologram_init(AgHologram *h, double sr) {
    memset(h,0,sizeof(*h));
    h->sr=sr>0?sr:AG_SR_DEFAULT;
    h->gain=0.52f;
    ag_osc_init(&h->osc1, AG_OSC_SINE, sr);
    ag_osc_init(&h->osc2, AG_OSC_SINE, sr);
    ag_osc_init(&h->mod, AG_OSC_SINE, sr); ag_osc_set_freq(&h->mod, 5.2f);
    ag_biquad_init(&h->bp); ag_biquad_set(&h->bp, AG_FILTER_BP, 2000,1.2f,0,(float)sr);
    ag_biquad_init(&h->lp); ag_biquad_set(&h->lp, AG_FILTER_LP, 3800,0.72f,0,(float)sr);
    ag_biquad_init(&h->hp); ag_biquad_set(&h->hp, AG_FILTER_HP, 120,0.7f,0,(float)sr);
    ag_lfo_init(&h->lfo, AG_OSC_SINE, 0.6, sr, 0.12f);
    AgADSR adsr={0.08f,0.5f,0.0f,0.4f,0.6f,1.2f,1.0f,0,0};
    ag_env_init(&h->env, adsr, sr);
    ag_dcblock_init(&h->dc);
}
void ag_hologram_trigger(AgHologram *h, float freq, float duration) {
    if(freq<100) freq=100;
    ag_osc_set_freq(&h->osc1, freq);
    ag_osc_set_freq(&h->osc2, freq*1.007f);
    ag_osc_set_freq(&h->mod, freq*0.25f);
    AgADSR adsr={duration*0.12f,duration*0.5f,0.0f,duration*0.38f,0.6f,1.2f,1.0f,0,0};
    ag_env_init(&h->env, adsr, h->sr);
    ag_env_trigger(&h->env);
    h->active=1;
    ag_biquad_set(&h->bp, AG_FILTER_BP, freq*1.2f,1.1f,0,(float)h->sr);
}
float ag_hologram_next(AgHologram *h) {
    if(!h->active) return 0.0f;
    float env=ag_env_next_hq(&h->env);
    if(ag_env_is_idle(&h->env)){ h->active=0; return 0.0f; }
    float lfo=ag_lfo_next_smooth(&h->lfo)*0.15f;
    float mod=ag_osc_next_hq(&h->mod)*0.25f;
    float s1=ag_osc_next_hq(&h->osc1);
    float s2=ag_osc_next_hq(&h->osc2);
    float mix=(s1*0.6f + s2*0.4f)*(1.0f+mod+lfo);
    mix=ag_biquad_process_hq(&h->bp, mix);
    mix=ag_biquad_process_hq(&h->lp, mix);
    mix=ag_biquad_process_hq(&h->hp, mix);
    mix=ag_dcblock_process(&h->dc, mix);
    mix=tanhf(mix*0.85f)*1.08f;
    return mix*env*h->gain;
}
int ag_hologram_active(const AgHologram *h){ return h->active; }

/* ---------- Engine ---------- */
void ag_scifi_engine_init(AgScifiEngine *e, double sr, float base_freq) {
    memset(e,0,sizeof(*e));
    e->sr=sr>0?sr:AG_SR_DEFAULT;
    e->gain=0.55f;
    e->thrust=0.3f;
    ag_osc_init(&e->osc1, AG_OSC_SAW, sr); ag_osc_set_freq(&e->osc1, base_freq);
    ag_osc_init(&e->osc2, AG_OSC_SAW, sr); ag_osc_set_freq(&e->osc2, base_freq*0.994f);
    ag_biquad_init(&e->lp); ag_biquad_set(&e->lp, AG_FILTER_LP, 800,0.72f,0,(float)sr);
    ag_biquad_init(&e->bp); ag_biquad_set(&e->bp, AG_FILTER_BP, 120,1.0f,0,(float)sr);
    ag_lfo_init(&e->rumble_lfo, AG_OSC_SINE, 12.0, sr, 0.25f);
    ag_noise_init(&e->noise, 0xE11);
    ag_dcblock_init(&e->dc);
}
void ag_scifi_engine_set_thrust(AgScifiEngine *e, float thrust) {
    e->thrust=ag_clamp_f(thrust,0,1);
    float freq = 40 + thrust*120;
    ag_osc_set_freq(&e->osc1, freq);
    ag_osc_set_freq(&e->osc2, freq*0.994f);
    ag_biquad_set(&e->lp, AG_FILTER_LP, 300 + thrust*1200,0.72f,0,(float)e->sr);
}
float ag_scifi_engine_next(AgScifiEngine *e) {
    float s1=ag_osc_next_hq(&e->osc1);
    float s2=ag_osc_next_hq(&e->osc2);
    float rumble=ag_lfo_next_smooth(&e->rumble_lfo)*e->thrust*0.3f;
    float n=ag_noise_brown(&e->noise)*0.15f*e->thrust;
    float mix=(s1*0.5f + s2*0.5f)*(0.7f + rumble) + n;
    mix=ag_biquad_process_hq(&e->lp, mix);
    float low=ag_biquad_process_hq(&e->bp, mix)*0.5f;
    mix=mix*0.7f + low*0.5f;
    mix=ag_dcblock_process(&e->dc, mix);
    mix=tanhf(mix*0.85f)*1.1f;
    return mix*e->gain*(0.4f + e->thrust*0.8f);
}

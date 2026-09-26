#include "ag_nature.h"
#include <string.h>
#include <math.h>

/* ---------- Bird HQ ---------- */
void ag_bird_init(AgBird *b, double sr, int species) {
    memset(b,0,sizeof(*b));
    b->sr=sr>0?sr:AG_SR_DEFAULT;
    b->species=species % 5;
    b->gain=0.85f;
    /* species base freqs and character */
    switch(b->species){
        case 0: b->base_freq=2200; b->chirp_rate=1.2f; b->syllable_gap=0.06f; break; /* sparrow fast trill */
        case 1: b->base_freq=2600; b->chirp_rate=0.8f; b->syllable_gap=0.12f; break; /* robin melodic */
        case 2: b->base_freq=1800; b->chirp_rate=0.5f; b->syllable_gap=0.08f; break; /* crow harsh */
        case 3: b->base_freq=1200; b->chirp_rate=0.4f; b->syllable_gap=0.18f; break; /* owl low */
        case 4: b->base_freq=2800; b->chirp_rate=0.7f; b->syllable_gap=0.15f; break; /* seagull long */
        default: b->base_freq=2200; b->chirp_rate=0.9f; b->syllable_gap=0.1f; break;
    }
    ag_osc_init(&b->osc, AG_OSC_SINE, sr);
    ag_osc_init(&b->mod, AG_OSC_SINE, sr);
    ag_osc_init(&b->vib_lfo, AG_OSC_SINE, sr);
    ag_osc_init(&b->sweep_lfo, AG_OSC_SINE, sr);
    ag_osc_set_freq(&b->mod, 85);
    ag_osc_set_freq(&b->vib_lfo, 12.0f);
    ag_osc_set_freq(&b->sweep_lfo, 18.0f);
    AgADSR adsr = {0.008f,0.10f,0.0f,0.07f,0.75f,1.3f,1.0f,0,0};
    ag_env_init(&b->env, adsr, sr);
    AgADSR adsr2 = {0.006f,0.09f,0.0f,0.06f,0.7f,1.2f,1.0f,0,0};
    ag_env_init(&b->env2, adsr2, sr);
    ag_biquad_init(&b->filter); ag_biquad_set(&b->filter, AG_FILTER_BP, b->base_freq, 2.4f, 0, (float)sr);
    ag_biquad_init(&b->formant); ag_biquad_set(&b->formant, AG_FILTER_BP, b->base_freq*1.8f, 1.6f, 0, (float)sr);
    ag_biquad_init(&b->hp); ag_biquad_set(&b->hp, AG_FILTER_HP, 800.0f, 0.7f, 0, (float)sr);
    ag_rng_seed(&b->rng, 0xB11D + species*101);
    b->next_call=ag_rng_range_f32(&b->rng, 0.5f, 2.0f);
    b->sweep_start=b->base_freq*0.85f;
    b->sweep_end=b->base_freq*1.25f;
}
void ag_bird_trigger(AgBird *b) {
    float var = ag_rng_range_f32(&b->rng, -250, 450);
    float f0 = b->base_freq + var;
    float f1 = f0 * ag_rng_range_f32(&b->rng, 0.9f, 1.35f);
    /* species specific sweep */
    switch(b->species){
        case 0: /* sparrow - fast up */
            b->sweep_start=f0*0.9f; b->sweep_end=f0*1.4f; b->sweep_time=0.08f; break;
        case 1: /* robin - melodic down-up */
            b->sweep_start=f0*1.2f; b->sweep_end=f0*0.85f; b->sweep_time=0.14f; break;
        case 2: /* crow - harsh down */
            b->sweep_start=f0*1.1f; b->sweep_end=f0*0.7f; b->sweep_time=0.18f; break;
        case 3: /* owl low - slight down */
            b->sweep_start=f0*1.05f; b->sweep_end=f0*0.92f; b->sweep_time=0.22f; break;
        case 4: /* seagull - long bend */
            b->sweep_start=f0*0.8f; b->sweep_end=f0*1.5f; b->sweep_time=0.35f; break;
        default: b->sweep_start=f0*0.9f; b->sweep_end=f0*1.3f; b->sweep_time=0.12f; break;
    }
    ag_osc_set_freq(&b->osc, b->sweep_start);
    ag_osc_set_freq(&b->mod, ag_rng_range_f32(&b->rng, 45, 130));
    ag_biquad_set(&b->filter, AG_FILTER_BP, f0, 2.6f, 0, (float)b->sr);
    ag_biquad_set(&b->formant, AG_FILTER_BP, f0*1.85f, 1.7f, 0, (float)b->sr);
    ag_env_trigger(&b->env);
    b->active=1;
    b->syllable=0;
    b->timer=0;
    (void)f1;
}
float ag_bird_next(AgBird *b) {
    float l,r; ag_bird_next_stereo(b,&l,&r); return (l+r)*0.5f;
}
void ag_bird_next_stereo(AgBird *b, float *out_l, float *out_r) {
    b->timer+=1.0/b->sr;
    if(!b->active){ *out_l=0; *out_r=0; return; }
    float env=ag_env_next(&b->env);
    float env2=0;
    /* handle second syllable */
    if(b->syllable==0 && b->timer > b->sweep_time){
        b->syllable=1;
        /* second syllable - slightly different */
        float f2 = b->base_freq * ag_rng_range_f32(&b->rng, 0.9f, 1.2f);
        ag_osc_set_freq(&b->osc, f2);
        ag_env_trigger(&b->env2);
    }
    if(b->syllable==1) env2=ag_env_next(&b->env2);

    if(ag_env_is_idle(&b->env) && (b->syllable==0 || ag_env_is_idle(&b->env2))){
        b->active=0;
        *out_l=0; *out_r=0; return;
    }

    /* frequency sweep */
    float sweep_t = (float)(b->timer / b->sweep_time);
    if(sweep_t>1) sweep_t=1;
    /* smoothstep */
    float st = sweep_t*sweep_t*(3.0f-2.0f*sweep_t);
    float cur_freq = b->sweep_start + (b->sweep_end - b->sweep_start)*st;

    /* FM + vibrato */
    float mod = ag_osc_next(&b->mod) * 220.0f * (0.5f + env*0.5f);
    float vib = ag_osc_next(&b->vib_lfo) * 35.0f * env;
    ag_osc_set_freq(&b->osc, cur_freq + mod + vib);

    float s = ag_osc_next(&b->osc);
    /* second harmonic for brightness */
    float s2 = sinf((float)(b->osc.phase * 2.0 * AG_PI * 2.0)) * 0.18f * env;
    float mixed = s*0.85f + s2*0.25f;

    mixed = ag_biquad_process(&b->filter, mixed);
    mixed = ag_biquad_process(&b->formant, mixed);
    mixed = ag_biquad_process(&b->hp, mixed);

    float out = mixed * (env*0.7f + env2*0.5f) * b->gain;

    /* slight stereo from formant */
    *out_l = out * 0.6f;
    *out_r = out * 0.4f;
}
void ag_bird_auto(AgBird *b, float density) {
    if(b->timer >= b->next_call){
        b->timer=0;
        b->next_call = ag_rng_range_f32(&b->rng, 0.6f, 4.5f) / (density>0.01f?density:0.01f);
        if(ag_rng_next_f32(&b->rng) < density * 0.85f) ag_bird_trigger(b);
    }
}

/* ---------- Cricket HQ ---------- */
void ag_cricket_init(AgCricket *c, double sr) {
    memset(c,0,sizeof(*c));
    c->sr=sr>0?sr:AG_SR_DEFAULT;
    c->gain=0.55f;
    c->am_depth=0.85f;
    c->chirp_len=0.18f;
    ag_osc_init(&c->osc1, AG_OSC_SINE, sr); ag_osc_set_freq(&c->osc1, 4500);
    ag_osc_init(&c->osc2, AG_OSC_SINE, sr); ag_osc_set_freq(&c->osc2, 4620);
    ag_osc_init(&c->am_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&c->am_lfo, 30.0f);
    ag_osc_init(&c->pulse_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&c->pulse_lfo, 55.0f);
    AgADSR adsr = {0.004f,0.08f,0.0f,0.025f,1,1,1,0,0};
    ag_env_init(&c->env, adsr, sr);
    AgADSR adsr2 = {0.003f,0.06f,0.0f,0.02f,1,1,1,0,0};
    ag_env_init(&c->env2, adsr2, sr);
    ag_biquad_init(&c->bp1); ag_biquad_set(&c->bp1, AG_FILTER_BP, 4550, 3.5f, 0, (float)sr);
    ag_biquad_init(&c->bp2); ag_biquad_set(&c->bp2, AG_FILTER_BP, 4600, 3.0f, 0, (float)sr);
    ag_rng_seed(&c->rng, 0xC11C);
    c->next_chirp=0.15;
    ag_env_trigger(&c->env);
    c->active=1;
}
float ag_cricket_next(AgCricket *c) {
    float l,r; ag_cricket_next_stereo(c,&l,&r); return (l+r)*0.5f;
}
void ag_cricket_next_stereo(AgCricket *c, float *out_l, float *out_r) {
    c->timer+=1.0/c->sr;
    if(c->timer >= c->next_chirp){
        c->timer=0;
        c->next_chirp = ag_rng_range_f32(&c->rng, 0.12f, 0.45f);
        /* chirp is burst of pulses */
        ag_env_trigger(&c->env);
        ag_env_trigger(&c->env2);
        c->active=1;
        /* slight freq variation */
        float f1 = 4450 + ag_rng_range_f32(&c->rng, -80, 120);
        ag_osc_set_freq(&c->osc1, f1);
        ag_osc_set_freq(&c->osc2, f1*1.027f);
        ag_biquad_set(&c->bp1, AG_FILTER_BP, f1, 3.8f, 0, (float)c->sr);
        ag_biquad_set(&c->bp2, AG_FILTER_BP, f1*1.027f, 3.2f, 0, (float)c->sr);
    }
    if(!c->active){ *out_l=0; *out_r=0; return; }
    float env=ag_env_next(&c->env);
    float env2=ag_env_next(&c->env2);
    if(ag_env_is_idle(&c->env) && ag_env_is_idle(&c->env2)) c->active=0;

    float am = ag_osc_next(&c->am_lfo) * 0.5f + 0.5f;
    am = powf(am, 0.7f); /* shape */
    float pulse = ag_osc_next(&c->pulse_lfo) > 0 ? 1.0f : 0.15f;

    float s1=ag_osc_next(&c->osc1);
    float s2=ag_osc_next(&c->osc2);
    s1=ag_biquad_process(&c->bp1, s1);
    s2=ag_biquad_process(&c->bp2, s2);
    float s = (s1*0.6f + s2*0.4f) * (0.3f + am*0.7f*c->am_depth) * pulse * (env*0.7f + env2*0.4f);

    *out_l = s * c->gain * 0.55f;
    *out_r = s * c->gain * 0.45f;
}
void ag_cricket_auto(AgCricket *c, float density){ (void)c; (void)density; }

/* ---------- Cicada HQ ---------- */
void ag_cicada_init(AgCicada *c, double sr) {
    memset(c,0,sizeof(*c));
    c->sr=sr>0?sr:AG_SR_DEFAULT;
    c->gain=0.38f;
    c->buzz_freq=120.0f;
    ag_noise_init(&c->noise, 0xC1CA);
    ag_biquad_init(&c->bp); ag_biquad_set(&c->bp, AG_FILTER_BP, 4200.0f, 3.2f, 0, (float)sr);
    ag_biquad_init(&c->bp2);ag_biquad_set(&c->bp2,AG_FILTER_BP, 3800.0f, 2.0f,0,(float)sr);
    ag_biquad_init(&c->hp); ag_biquad_set(&c->hp, AG_FILTER_HP, 1500.0f,0.7f,0,(float)sr);
    ag_osc_init(&c->am_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&c->am_lfo, 122.0f);
    ag_osc_init(&c->fm_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&c->fm_lfo, 8.5f);
    ag_osc_init(&c->pulse_osc, AG_OSC_SINE, sr); ag_osc_set_freq(&c->pulse_osc, 240.0f);
    ag_rng_seed(&c->rng, 0xC1CA);
}
float ag_cicada_next(AgCicada *c) {
    float l,r; ag_cicada_next_stereo(c,&l,&r); return (l+r)*0.5f;
}
void ag_cicada_next_stereo(AgCicada *c, float *out_l, float *out_r) {
    float n = ag_noise_white(&c->noise);
    n = ag_biquad_process(&c->bp, n);
    float n2 = ag_biquad_process(&c->bp2, n) * 0.4f;
    float mixed = n*0.7f + n2*0.3f;
    mixed = ag_biquad_process(&c->hp, mixed);

    float am = ag_osc_next(&c->am_lfo) * 0.5f + 0.5f;
    am = powf(am, 0.6f);
    float fm = ag_osc_next(&c->fm_lfo) * 0.15f;
    float pulse = ag_osc_next(&c->pulse_osc) > 0.2f ? 1.0f : 0.3f;

    c->timer+=1.0/c->sr;
    if(c->timer>0.4){
        c->timer=0;
        float fc = ag_rng_range_f32(&c->rng, 3600, 5200);
        float fc2 = fc * ag_rng_range_f32(&c->rng, 0.85f, 1.15f);
        ag_biquad_set(&c->bp, AG_FILTER_BP, fc, 3.4f, 0, (float)c->sr);
        ag_biquad_set(&c->bp2, AG_FILTER_BP, fc2, 2.2f, 0, (float)c->sr);
        ag_osc_set_freq(&c->am_lfo, ag_rng_range_f32(&c->rng, 115, 135));
    }

    float out = mixed * am * pulse * (0.8f + fm) * c->gain;
    *out_l = out*0.55f;
    *out_r = out*0.45f;
}

/* ---------- Frog HQ ---------- */
void ag_frog_init(AgFrog *f, double sr) {
    memset(f,0,sizeof(*f));
    f->sr=sr>0?sr:AG_SR_DEFAULT;
    f->gain=0.65f;
    f->base_freq=200.0f;
    ag_osc_init(&f->osc, AG_OSC_SINE, sr); ag_osc_set_freq(&f->osc, 200);
    ag_osc_init(&f->osc2, AG_OSC_SINE, sr); ag_osc_set_freq(&f->osc2, 400);
    ag_osc_init(&f->sac_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&f->sac_lfo, 6.5f);
    ag_biquad_init(&f->formant); ag_biquad_set(&f->formant, AG_FILTER_BP, 600.0f, 1.6f, 0, (float)sr);
    ag_biquad_init(&f->formant2);ag_biquad_set(&f->formant2,AG_FILTER_BP,1200.0f,1.2f,0,(float)sr);
    ag_biquad_init(&f->lp); ag_biquad_set(&f->lp, AG_FILTER_LP, 1800.0f,0.7f,0,(float)sr);
    AgADSR adsr = {0.012f,0.22f,0.0f,0.12f,1,1,1,0,0};
    ag_env_init(&f->env, adsr, sr);
    AgADSR adsr2 = {0.008f,0.18f,0.0f,0.09f,1,1,1,0,0};
    ag_env_init(&f->env2, adsr2, sr);
    ag_rng_seed(&f->rng, 0xF1109);
    f->next_croak=ag_rng_range_f32(&f->rng, 0.8f, 2.0f);
    f->croak_count=0;
}
float ag_frog_next(AgFrog *f) {
    float l,r; ag_frog_next_stereo(f,&l,&r); return (l+r)*0.5f;
}
void ag_frog_next_stereo(AgFrog *f, float *out_l, float *out_r) {
    f->timer+=1.0/f->sr;
    if(f->timer >= f->next_croak){
        f->timer=0;
        f->next_croak = ag_rng_range_f32(&f->rng, 0.9f, 3.2f);
        float freq = ag_rng_range_f32(&f->rng, 140, 360);
        f->base_freq=freq;
        ag_osc_set_freq(&f->osc, freq);
        ag_osc_set_freq(&f->osc2, freq*2.02f);
        ag_biquad_set(&f->formant, AG_FILTER_BP, freq*2.6f, 1.4f, 0, (float)f->sr);
        ag_biquad_set(&f->formant2, AG_FILTER_BP, freq*4.1f, 1.1f, 0, (float)f->sr);
        ag_osc_set_freq(&f->sac_lfo, ag_rng_range_f32(&f->rng, 5.0f, 8.0f));
        ag_env_trigger(&f->env);
        if(f->croak_count % 2 ==0) ag_env_trigger(&f->env2);
        f->croak_count++;
        f->active=1;
    }
    if(!f->active){ *out_l=0; *out_r=0; return; }
    float env=ag_env_next(&f->env);
    float env2=ag_env_next(&f->env2);
    if(ag_env_is_idle(&f->env) && ag_env_is_idle(&f->env2)) f->active=0;

    float sac = ag_osc_next(&f->sac_lfo) * 0.25f;
    float s1=ag_osc_next(&f->osc);
    float s2=ag_osc_next(&f->osc2) * 0.35f * (0.8f + sac);
    float mixed = (s1*0.7f + s2*0.4f) * (env*0.7f + env2*0.4f);
    mixed = ag_biquad_process(&f->formant, mixed);
    float f2 = ag_biquad_process(&f->formant2, mixed*0.5f);
    mixed = mixed*0.7f + f2*0.4f;
    mixed = ag_biquad_process(&f->lp, mixed);

    *out_l = mixed * f->gain * 0.55f;
    *out_r = mixed * f->gain * 0.45f;
}
void ag_frog_auto(AgFrog *f, float density){ (void)f; (void)density; }

/* ---------- Swarm HQ ---------- */
void ag_swarm_init(AgInsectSwarm *s, double sr) {
    memset(s,0,sizeof(*s));
    s->sr=sr>0?sr:AG_SR_DEFAULT;
    s->gain=0.32f;
    s->density=0.55f;
    s->doppler=0.0f;
    ag_rng_seed(&s->rng, 0x5A11A);
    ag_osc_init(&s->swarm_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&s->swarm_lfo, 0.23f);
    for(int i=0;i<AG_SWARM_MAX;i++){
        ag_osc_init(&s->grains[i].osc, AG_OSC_SINE, sr);
        float freq = ag_rng_range_f32(&s->rng, 3000, 8500);
        ag_osc_set_freq(&s->grains[i].osc, freq);
        s->grains[i].pan = ag_rng_range_f32(&s->rng, -1,1);
        s->grains[i].active=0;
        s->grains[i].dur=ag_rng_range_f32(&s->rng, 0.02f, 0.08f);
        s->grains[i].gain=ag_rng_range_f32(&s->rng, 0.15f, 0.45f);
    }
}
float ag_swarm_next(AgInsectSwarm *s) {
    float l,r; ag_swarm_next_stereo(s,&l,&r); return (l+r)*0.5f;
}
void ag_swarm_next_stereo(AgInsectSwarm *s, float *out_l, float *out_r) {
    s->timer+=1.0/s->sr;
    float swarm_mod = ag_osc_next(&s->swarm_lfo) * 0.15f;
    if(s->timer > 0.03f){
        s->timer=0;
        for(int i=0;i<AG_SWARM_MAX;i++){
            if(!s->grains[i].active && ag_rng_next_f32(&s->rng) < s->density*0.28f){
                float freq = ag_rng_range_f32(&s->rng, 2800, 9200) * (1.0f + swarm_mod);
                ag_osc_set_freq(&s->grains[i].osc, freq);
                s->grains[i].osc.phase = ag_rng_next_f32(&s->rng);
                s->grains[i].active=1;
                s->grains[i].age=0;
                s->grains[i].dur=ag_rng_range_f32(&s->rng, 0.015f, 0.09f);
                s->grains[i].pan = ag_rng_range_f32(&s->rng, -1,1);
                s->grains[i].gain = ag_rng_range_f32(&s->rng, 0.12f, 0.42f);
                s->grains[i].freq=freq;
                break;
            }
        }
    }
    float ml=0,mr=0;
    for(int i=0;i<AG_SWARM_MAX;i++){
        if(!s->grains[i].active) continue;
        s->grains[i].age+=1.0/s->sr;
        float t = (float)(s->grains[i].age / s->grains[i].dur);
        if(t>=1.0f){ s->grains[i].active=0; continue; }
        /* Hanning envelope */
        float env = 0.5f - 0.5f * cosf(t * 2.0f * (float)AG_PI);
        /* doppler - slight freq slide */
        float freq_slide = s->grains[i].freq * (1.0f + sinf(t*(float)AG_PI)*0.02f);
        ag_osc_set_freq(&s->grains[i].osc, freq_slide);
        float samp = ag_osc_next(&s->grains[i].osc) * env * s->grains[i].gain;
        float pl,pr; ag_buffer_pan_stereo(samp, s->grains[i].pan, &pl, &pr);
        ml+=pl; mr+=pr;
    }
    *out_l=ml*s->gain;
    *out_r=mr*s->gain;
}

/* ---------- Owl HQ ---------- */
void ag_owl_init(AgOwl *o, double sr) {
    memset(o,0,sizeof(*o));
    o->sr=sr>0?sr:AG_SR_DEFAULT;
    o->gain=0.55f;
    ag_osc_init(&o->osc, AG_OSC_SINE, sr); ag_osc_set_freq(&o->osc, 380);
    ag_osc_init(&o->osc2, AG_OSC_SINE, sr); ag_osc_set_freq(&o->osc2, 570);
    ag_osc_init(&o->vib_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&o->vib_lfo, 4.5f);
    AgADSR adsr = {0.055f,0.38f,0.0f,0.22f,1,1,1,0,0};
    ag_env_init(&o->env, adsr, sr);
    AgADSR adsr2 = {0.045f,0.32f,0.0f,0.18f,1,1,1,0,0};
    ag_env_init(&o->env2, adsr2, sr);
    ag_biquad_init(&o->filter); ag_biquad_set(&o->filter, AG_FILTER_LP, 850.0f, 0.75f, 0, (float)sr);
    ag_biquad_init(&o->formant); ag_biquad_set(&o->formant, AG_FILTER_BP, 620.0f, 1.3f, 0, (float)sr);
    ag_biquad_init(&o->formant2);ag_biquad_set(&o->formant2,AG_FILTER_BP,1150.0f,1.1f,0,(float)sr);
    ag_rng_seed(&o->rng, 0x0A1);
    o->next_hoot=ag_rng_range_f32(&o->rng, 2.5f, 5.5f);
    o->hoot_phase=0;
}
float ag_owl_next(AgOwl *o) {
    float l,r; ag_owl_next_stereo(o,&l,&r); return (l+r)*0.5f;
}
void ag_owl_next_stereo(AgOwl *o, float *out_l, float *out_r) {
    o->timer+=1.0/o->sr;
    if(o->hoot_phase==0 && o->timer >= o->next_hoot){
        o->timer=0;
        o->hoot_phase=1;
        o->hoot_timer=0;
        float base = ag_rng_range_f32(&o->rng, 350, 450);
        ag_osc_set_freq(&o->osc, base);
        ag_osc_set_freq(&o->osc2, base*1.52f);
        ag_biquad_set(&o->formant, AG_FILTER_BP, base*1.6f, 1.4f, 0, (float)o->sr);
        ag_biquad_set(&o->formant2, AG_FILTER_BP, base*2.9f, 1.2f, 0, (float)o->sr);
        ag_env_trigger(&o->env);
        o->active=1;
    }
    /* second hoot after gap */
    if(o->hoot_phase==1){
        o->hoot_timer+=1.0/o->sr;
        if(o->hoot_timer > 0.32f){
            o->hoot_phase=2;
            o->hoot_timer=0;
            ag_env_trigger(&o->env2);
            float base2 = o->osc.freq * ag_rng_range_f32(&o->rng, 0.88f, 1.08f);
            ag_osc_set_freq(&o->osc, base2);
            ag_osc_set_freq(&o->osc2, base2*1.51f);
        }
    }
    if(o->hoot_phase==2){
        o->hoot_timer+=1.0/o->sr;
        if(o->hoot_timer > 1.2f){
            o->hoot_phase=0;
            o->timer=0;
            o->next_hoot = ag_rng_range_f32(&o->rng, 2.5f, 7.0f);
        }
    }

    if(!o->active){ *out_l=0; *out_r=0; return; }
    float env=ag_env_next(&o->env);
    float env2=ag_env_next(&o->env2);
    if(ag_env_is_idle(&o->env) && ag_env_is_idle(&o->env2) && o->hoot_phase==0) o->active=0;

    float vib = ag_osc_next(&o->vib_lfo) * 8.0f * (env+env2);
    ag_osc_set_freq(&o->osc, o->osc.freq + vib*0.1f);

    float s1=ag_osc_next(&o->osc);
    float s2=ag_osc_next(&o->osc2) * 0.38f;
    float mixed = (s1*0.7f + s2*0.4f) * (env*0.7f + env2*0.5f);
    mixed = ag_biquad_process(&o->filter, mixed);
    float f1 = ag_biquad_process(&o->formant, mixed);
    float f2 = ag_biquad_process(&o->formant2, mixed*0.5f);
    float out = mixed*0.5f + f1*0.4f + f2*0.25f;

    *out_l = out * o->gain * 0.55f;
    *out_r = out * o->gain * 0.45f;
}
void ag_owl_auto(AgOwl *o, float density){ (void)density; (void)o; }

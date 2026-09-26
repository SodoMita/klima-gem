#include "ag_water.h"
#include <string.h>
#include <math.h>

/* ---------- Ocean HQ ---------- */
void ag_ocean_init(AgOcean *o, double sr) {
    memset(o,0,sizeof(*o));
    o->sr=sr>0?sr:AG_SR_DEFAULT;
    o->gain=0.55f;
    o->swell_strength=0.45f;
    o->crash_chance=0.025f;
    o->base_freq=80.0f;
    o->low_gain=0.45f;
    o->mid_gain=0.65f;
    o->high_gain=0.25f;
    o->foam_gain=0.15f;
    ag_noise_init(&o->noise_low, 0x0CEA11);
    ag_noise_init(&o->noise_mid, 0x0CEA12);
    ag_noise_init(&o->noise_high, 0x0CEA13);
    ag_rng_seed(&o->rng, 0x0CEA11);
    ag_biquad_init(&o->lp_low);   ag_biquad_set(&o->lp_low, AG_FILTER_LP, 130.0f, 0.7f, 0, (float)sr);
    ag_biquad_init(&o->lp_mid);   ag_biquad_set(&o->lp_mid, AG_FILTER_LP, 850.0f, 0.65f, 0, (float)sr);
    ag_biquad_init(&o->lp_foam);  ag_biquad_set(&o->lp_foam, AG_FILTER_LP, 3800.0f, 0.7f, 0, (float)sr);
    ag_biquad_init(&o->hp_spray); ag_biquad_set(&o->hp_spray, AG_FILTER_HP, 1800.0f, 0.7f, 0, (float)sr);
    ag_biquad_init(&o->bp_crash); ag_biquad_set(&o->bp_crash, AG_FILTER_BP, 320.0f, 1.1f, 0, (float)sr);
    ag_biquad_init(&o->bp_splash);ag_biquad_set(&o->bp_splash,AG_FILTER_BP, 1200.0f,0.9f,0,(float)sr);
    ag_osc_init(&o->swell_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&o->swell_lfo, 0.07f);
    ag_osc_init(&o->swell_lfo2, AG_OSC_SINE, sr); ag_osc_set_freq(&o->swell_lfo2, 0.093f);
    o->swell_lfo2.phase=0.37f;
    ag_osc_init(&o->foam_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&o->foam_lfo, 0.31f);
    ag_osc_init(&o->crash_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&o->crash_lfo, 0.15f);
    ag_osc_init(&o->spray_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&o->spray_lfo, 0.51f);
    AgADSR adsr = {0.02f,0.8f,0.0f,1.2f,0.5f,1.5f,1.0f,0,0};
    ag_env_init(&o->crash_env, adsr, sr);
    o->decor_l=0.0f; o->decor_r=0.0f;
}
void ag_ocean_set(AgOcean *o, float gain, float swell_strength) {
    o->gain=ag_clamp_f(gain,0,1);
    o->swell_strength=ag_clamp_f(swell_strength,0,1);
}
float ag_ocean_next(AgOcean *o) {
    float l,r; ag_ocean_next_stereo(o,&l,&r); return (l+r)*0.5f;
}
void ag_ocean_next_stereo(AgOcean *o, float *out_l, float *out_r) {
    /* LFOs */
    float swell1 = ag_osc_next(&o->swell_lfo);
    float swell2 = ag_osc_next(&o->swell_lfo2);
    float foam_mod = ag_osc_next(&o->foam_lfo) * 0.3f;
    float crash_mod = ag_osc_next(&o->crash_lfo) * 0.5f + 0.5f;
    float spray_mod = ag_osc_next(&o->spray_lfo) * 0.2f;
    float swell = (swell1*0.6f + swell2*0.4f) * o->swell_strength;

    /* low rumble */
    float low_n = ag_noise_brown(&o->noise_low) * 0.7f + ag_noise_pink(&o->noise_low)*0.3f;
    low_n = ag_biquad_process(&o->lp_low, low_n);
    float low = low_n * o->low_gain * (0.7f + swell*0.5f);

    /* mid body - main ocean */
    float mid_n = ag_noise_pink(&o->noise_mid)*0.65f + ag_noise_white(&o->noise_mid)*0.2f + ag_noise_brown(&o->noise_mid)*0.15f;
    mid_n = ag_biquad_process(&o->lp_mid, mid_n);
    float mid = mid_n * o->mid_gain * (0.6f + swell*0.6f + crash_mod*0.25f);

    /* high foam/spray */
    float high_n = ag_noise_white(&o->noise_high)*0.6f + ag_noise_pink(&o->noise_high)*0.4f;
    high_n = ag_biquad_process(&o->hp_spray, high_n);
    high_n = ag_biquad_process(&o->lp_foam, high_n);
    float high = high_n * o->high_gain * (0.5f + foam_mod + spray_mod*0.3f + swell*0.2f);

    /* crash envelope handling */
    o->crash_timer += 1.0/o->sr;
    float crash = 0.0f;
    float splash = 0.0f;
    if(o->crash_timer > 1.2){
        o->crash_timer=0;
        if(ag_rng_next_f32(&o->rng) < o->crash_chance * (0.8f + swell*0.7f)){
            ag_env_trigger(&o->crash_env);
            o->crash_decay = 0;
        }
    }
    float crash_env = ag_env_next(&o->crash_env);
    if(crash_env > 0.001f){
        float burst = ag_noise_white(&o->noise_mid) * 1.5f + ag_noise_pink(&o->noise_mid)*0.5f;
        burst = ag_biquad_process(&o->bp_crash, burst);
        float burst2 = ag_noise_white(&o->noise_high)*0.8f;
        burst2 = ag_biquad_process(&o->bp_splash, burst2);
        crash = burst * crash_env * 0.9f;
        splash = burst2 * crash_env * 0.4f;
    }

    /* stereo decorrelation: slight different gains and filtered versions */
    o->decor_l += (ag_rng_next_f32(&o->rng)-0.5f)*0.001f;
    o->decor_r += (ag_rng_next_f32(&o->rng)-0.5f)*0.001f;
    o->decor_l = ag_clamp_f(o->decor_l, -0.08f, 0.08f);
    o->decor_r = ag_clamp_f(o->decor_r, -0.08f, 0.08f);
    float l = (low*0.9f + mid*0.55f + high*0.6f + crash*0.6f + splash*0.7f) * (1.0f+o->decor_l);
    float r = (low*0.9f + mid*0.45f + high*0.4f + crash*0.4f + splash*0.3f) * (1.0f+o->decor_r);
    /* slight stereo width from foam */
    l += high*0.15f;
    r -= high*0.1f;

    *out_l = l * o->gain;
    *out_r = r * o->gain;
}

/* ---------- River HQ ---------- */
void ag_river_init(AgRiver *r, double sr) {
    memset(r,0,sizeof(*r));
    r->sr=sr>0?sr:AG_SR_DEFAULT;
    r->gain=0.45f;
    r->turbulence=0.35f;
    r->deep_gain=0.5f;
    r->mid_gain=0.6f;
    r->surf_gain=0.25f;
    ag_noise_init(&r->noise_deep, 0x1112);
    ag_noise_init(&r->noise_mid, 0x1113);
    ag_noise_init(&r->noise_surf, 0x1114);
    ag_rng_seed(&r->rng, 0x1112);
    ag_biquad_init(&r->lp_deep); ag_biquad_set(&r->lp_deep, AG_FILTER_LP, 380.0f, 0.7f, 0, (float)sr);
    ag_biquad_init(&r->lp_mid);  ag_biquad_set(&r->lp_mid, AG_FILTER_LP, 1250.0f, 0.68f, 0, (float)sr);
    ag_biquad_init(&r->hp_surf); ag_biquad_set(&r->hp_surf, AG_FILTER_HP, 1800.0f, 0.7f, 0, (float)sr);
    ag_biquad_init(&r->bp_bubble); ag_biquad_set(&r->bp_bubble, AG_FILTER_BP, 900.0f, 1.2f, 0, (float)sr);
    ag_osc_init(&r->flow_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&r->flow_lfo, 0.31f);
    ag_osc_init(&r->flow_lfo2, AG_OSC_SINE, sr); ag_osc_set_freq(&r->flow_lfo2, 0.17f); r->flow_lfo2.phase=0.5f;
    ag_osc_init(&r->turb_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&r->turb_lfo, 1.13f);
    ag_osc_init(&r->hiss_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&r->hiss_lfo, 2.31f);
    r->bubble_next=0.5f;
}
float ag_river_next(AgRiver *r) {
    float l,rr; ag_river_next_stereo(r,&l,&rr); return (l+rr)*0.5f;
}
void ag_river_next_stereo(AgRiver *r, float *out_l, float *out_r) {
    float flow1 = ag_osc_next(&r->flow_lfo);
    float flow2 = ag_osc_next(&r->flow_lfo2);
    float turb = ag_osc_next(&r->turb_lfo) * r->turbulence;
    float hiss = ag_osc_next(&r->hiss_lfo) * 0.15f;

    float deep_n = ag_noise_brown(&r->noise_deep)*0.6f + ag_noise_pink(&r->noise_deep)*0.4f;
    deep_n = ag_biquad_process(&r->lp_deep, deep_n);
    float deep = deep_n * r->deep_gain * (0.8f + flow1*0.3f + flow2*0.2f);

    float mid_n = ag_noise_pink(&r->noise_mid)*0.7f + ag_noise_white(&r->noise_mid)*0.25f + ag_noise_brown(&r->noise_mid)*0.05f;
    mid_n = ag_biquad_process(&r->lp_mid, mid_n);
    float mid = mid_n * r->mid_gain * (1.0f + turb*0.4f + flow1*0.2f);

    float surf_n = ag_noise_white(&r->noise_surf)*0.7f + ag_noise_pink(&r->noise_surf)*0.3f;
    surf_n = ag_biquad_process(&r->hp_surf, surf_n);
    float surf = surf_n * r->surf_gain * (0.6f + hiss + turb*0.2f);

    /* occasional bubble pop */
    r->bubble_timer += 1.0/r->sr;
    float bubble=0;
    if(r->bubble_timer > r->bubble_next){
        r->bubble_timer=0;
        r->bubble_next = ag_rng_range_f32(&r->rng, 0.3f, 1.2f) / (r->turbulence*0.5f+0.3f);
        if(ag_rng_next_f32(&r->rng) < 0.4f){
            float b = ag_noise_white(&r->noise_mid)*0.6f;
            b = ag_biquad_process(&r->bp_bubble, b);
            bubble = b * 0.5f;
        }
    }

    /* stereo width: deep mostly mono, mid/surf stereo */
    float l = deep*0.5f + mid*0.6f + surf*0.7f + bubble*0.6f;
    float rr = deep*0.5f + mid*0.4f + surf*0.3f + bubble*0.4f;
    /* add slight decorrelation */
    l += surf*0.15f;
    rr -= surf*0.1f;
    *out_l = l * r->gain;
    *out_r = rr * r->gain;
}

/* ---------- Stream HQ ---------- */
void ag_stream_init(AgStream *s, double sr) {
    memset(s,0,sizeof(*s));
    ag_river_init(&s->river, sr);
    s->river.gain=0.38f;
    s->river.turbulence=0.45f;
    ag_biquad_init(&s->sparkle_bp); ag_biquad_set(&s->sparkle_bp, AG_FILTER_BP, 3800.0f, 1.4f, 0, (float)sr);
    ag_biquad_init(&s->sparkle_bp2);ag_biquad_set(&s->sparkle_bp2,AG_FILTER_BP,5200.0f,1.2f,0,(float)sr);
    ag_osc_init(&s->sparkle_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&s->sparkle_lfo, 0.8f);
    ag_rng_seed(&s->rng, 0x51A);
    s->sparkle_chance=0.035f;
    ag_osc_init(&s->droplet_osc, AG_OSC_SINE, sr);
    AgADSR adsr = {0.001f,0.08f,0.0f,0.03f,0.8f,1.2f,1.0f,0,0};
    ag_env_init(&s->droplet_env, adsr, sr);
    ag_biquad_init(&s->droplet_bp); ag_biquad_set(&s->droplet_bp, AG_FILTER_BP, 3000, 2.0f, 0, (float)sr);
    s->next_droplet=0.4f;
}
float ag_stream_next(AgStream *s) {
    float l,r; ag_stream_next_stereo(s,&l,&r); return (l+r)*0.5f;
}
void ag_stream_next_stereo(AgStream *s, float *l, float *r) {
    float rl, rr;
    ag_river_next_stereo(&s->river, &rl, &rr);
    float sparkle_lfo = ag_osc_next(&s->sparkle_lfo)*0.3f;
    float sparkle=0, sparkle_r=0;
    if(ag_rng_next_f32(&s->rng) < s->sparkle_chance * (1.0f+sparkle_lfo)){
        float n = ag_noise_white(&s->river.noise_mid)*0.9f;
        float f1 = ag_rng_range_f32(&s->rng, 3000, 6000);
        ag_biquad_set(&s->sparkle_bp, AG_FILTER_BP, f1, 1.5f, 0, (float)s->river.sr);
        float f2 = f1*1.4f;
        ag_biquad_set(&s->sparkle_bp2, AG_FILTER_BP, f2, 1.2f, 0, (float)s->river.sr);
        sparkle = ag_biquad_process(&s->sparkle_bp, n) * 0.5f + ag_biquad_process(&s->sparkle_bp2, n)*0.3f;
        sparkle_r = sparkle * ag_rng_range_f32(&s->rng, -0.3f, 0.8f);
        sparkle *= ag_rng_range_f32(&s->rng, 0.4f, 1.0f);
    }
    /* droplet */
    s->droplet_timer += 1.0/s->river.sr;
    if(s->droplet_timer > s->next_droplet){
        s->droplet_timer=0;
        s->next_droplet = ag_rng_range_f32(&s->rng, 0.2f, 0.9f);
        float freq = ag_rng_range_f32(&s->rng, 1800, 4500);
        ag_osc_set_freq(&s->droplet_osc, freq);
        ag_biquad_set(&s->droplet_bp, AG_FILTER_BP, freq, 2.2f, 0, (float)s->river.sr);
        ag_env_trigger(&s->droplet_env);
    }
    float drop_env = ag_env_next(&s->droplet_env);
    float droplet=0;
    if(drop_env>0.001f){
        droplet = ag_osc_next(&s->droplet_osc) * drop_env * 0.4f;
        droplet = ag_biquad_process(&s->droplet_bp, droplet);
    }
    *l = rl + sparkle*0.6f + droplet*0.5f;
    *r = rr + sparkle_r*0.6f + droplet*0.3f;
}

/* ---------- Waterfall HQ ---------- */
void ag_waterfall_init(AgWaterfall *wf, double sr) {
    memset(wf,0,sizeof(*wf));
    wf->sr=sr>0?sr:AG_SR_DEFAULT;
    wf->gain=0.62f;
    wf->roar=0.55f;
    wf->mist_gain=0.25f;
    wf->low_gain=0.5f;
    ag_noise_init(&wf->noise_low, 0xFA11);
    ag_noise_init(&wf->noise_mid, 0xFA12);
    ag_noise_init(&wf->noise_high, 0xFA13);
    ag_biquad_init(&wf->lp_low); ag_biquad_set(&wf->lp_low, AG_FILTER_LP, 160.0f, 0.7f, 0, (float)sr);
    ag_biquad_init(&wf->lp_mid); ag_biquad_set(&wf->lp_mid, AG_FILTER_LP, 900.0f, 0.65f, 0, (float)sr);
    ag_biquad_init(&wf->lp_high);ag_biquad_set(&wf->lp_high,AG_FILTER_LP,3200.0f,0.7f,0,(float)sr);
    ag_biquad_init(&wf->hp_mist);ag_biquad_set(&wf->hp_mist,AG_FILTER_HP,1100.0f,0.7f,0,(float)sr);
    ag_biquad_init(&wf->bp_roar);ag_biquad_set(&wf->bp_roar,AG_FILTER_BP,210.0f,0.9f,0,(float)sr);
    ag_osc_init(&wf->roar_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&wf->roar_lfo, 0.12f);
    ag_osc_init(&wf->roar_lfo2, AG_OSC_SINE, sr); ag_osc_set_freq(&wf->roar_lfo2, 0.071f); wf->roar_lfo2.phase=0.6f;
    ag_osc_init(&wf->mist_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&wf->mist_lfo, 0.93f);
    ag_rng_seed(&wf->rng, 0xFA11);
}
float ag_waterfall_next(AgWaterfall *wf) {
    float l,r; ag_waterfall_next_stereo(wf,&l,&r); return (l+r)*0.5f;
}
void ag_waterfall_next_stereo(AgWaterfall *wf, float *out_l, float *out_r) {
    float roar1 = ag_osc_next(&wf->roar_lfo) * wf->roar;
    float roar2 = ag_osc_next(&wf->roar_lfo2) * wf->roar * 0.6f;
    float mist = ag_osc_next(&wf->mist_lfo) * 0.25f;

    float low_n = ag_noise_brown(&wf->noise_low)*0.7f + ag_noise_pink(&wf->noise_low)*0.3f;
    low_n = ag_biquad_process(&wf->lp_low, low_n);
    float low_roar = ag_biquad_process(&wf->bp_roar, low_n) * 0.6f;
    float low = (low_n*0.6f + low_roar*0.5f) * wf->low_gain * (0.7f + roar1*0.4f + roar2*0.2f);

    float mid_n = ag_noise_pink(&wf->noise_mid)*0.6f + ag_noise_white(&wf->noise_mid)*0.35f + ag_noise_brown(&wf->noise_mid)*0.05f;
    mid_n = ag_biquad_process(&wf->lp_mid, mid_n);
    float mid = mid_n * 0.7f * (0.8f + roar1*0.3f);

    float high_n = ag_noise_white(&wf->noise_high)*0.65f + ag_noise_pink(&wf->noise_high)*0.35f;
    high_n = ag_biquad_process(&wf->lp_high, high_n);
    high_n = ag_biquad_process(&wf->hp_mist, high_n);
    float high = high_n * wf->mist_gain * (0.6f + mist + roar2*0.2f);

    /* stereo decorrelation: low mono, mid/high stereo */
    float l = low*0.5f + mid*0.6f + high*0.7f;
    float r = low*0.5f + mid*0.4f + high*0.3f;
    /* add slight random width */
    l += high*0.12f * (0.8f + mist);
    r += high*0.08f * (0.8f - mist);
    *out_l = l * wf->gain;
    *out_r = r * wf->gain;
}

/* ---------- Drip HQ - modal synthesis ---------- */
void ag_drip_init(AgDrip *d, double sr) {
    memset(d,0,sizeof(*d));
    d->sr=sr>0?sr:AG_SR_DEFAULT;
    d->gain=0.65f;
    d->decay=0.92f;
    ag_osc_init(&d->osc_main, AG_OSC_SINE, sr);
    ag_osc_init(&d->osc_mode2, AG_OSC_SINE, sr);
    ag_osc_init(&d->osc_mode3, AG_OSC_SINE, sr);
    AgADSR adsr = {0.0008f,0.18f,0.0f,0.06f,0.4f,1.8f,1.0f,0,0};
    ag_env_init(&d->env_main, adsr, sr);
    AgADSR adsr2 = {0.001f,0.35f,0.0f,0.12f,0.3f,1.2f,1.0f,0,0};
    ag_env_init(&d->env_ripple, adsr2, sr);
    ag_biquad_init(&d->filter_main); ag_biquad_set(&d->filter_main, AG_FILTER_BP, 1200, 2.8f, 0, (float)sr);
    ag_biquad_init(&d->filter_mode2); ag_biquad_set(&d->filter_mode2, AG_FILTER_BP, 2400, 2.2f, 0, (float)sr);
    ag_biquad_init(&d->filter_mode3); ag_biquad_set(&d->filter_mode3, AG_FILTER_BP, 3600, 1.8f, 0, (float)sr);
    ag_biquad_init(&d->hp_click); ag_biquad_set(&d->hp_click, AG_FILTER_HP, 3000, 0.7f, 0, (float)sr);
    ag_rng_seed(&d->rng, 0xD11A);
    d->next_drip_time=0.5;
    memset(d->early_delay,0,sizeof(d->early_delay));
}
void ag_drip_trigger(AgDrip *d, float freq, float gain) {
    float f1 = freq;
    float f2 = freq * 2.13f; /* inharmonic */
    float f3 = freq * 3.47f;
    ag_osc_set_freq(&d->osc_main, f1);
    ag_osc_set_freq(&d->osc_mode2, f2);
    ag_osc_set_freq(&d->osc_mode3, f3);
    ag_biquad_set(&d->filter_main, AG_FILTER_BP, f1, 3.2f, 0, (float)d->sr);
    ag_biquad_set(&d->filter_mode2, AG_FILTER_BP, f2, 2.5f, 0, (float)d->sr);
    ag_biquad_set(&d->filter_mode3, AG_FILTER_BP, f3, 2.0f, 0, (float)d->sr);
    ag_biquad_set(&d->hp_click, AG_FILTER_HP, f1*2.0f, 0.7f, 0, (float)d->sr);
    ag_env_trigger(&d->env_main);
    ag_env_trigger(&d->env_ripple);
    d->active=1;
    d->gain=gain;
    d->drip_freq=f1;
    d->ripple_freq=f1*0.35f;
    d->decay=ag_rng_range_f32(&d->rng, 0.88f, 0.96f);
}
float ag_drip_next(AgDrip *d) {
    float l,r; ag_drip_next_stereo(d,&l,&r); return (l+r)*0.5f;
}
void ag_drip_next_stereo(AgDrip *d, float *out_l, float *out_r) {
    d->timer += 1.0/d->sr;
    float out=0;
    if(d->active){
        float env=ag_env_next(&d->env_main);
        float env2=ag_env_next(&d->env_ripple);
        if(ag_env_is_idle(&d->env_main) && ag_env_is_idle(&d->env_ripple)) d->active=0;
        else {
            float s1=ag_osc_next(&d->osc_main);
            float s2=ag_osc_next(&d->osc_mode2) * 0.35f;
            float s3=ag_osc_next(&d->osc_mode3) * 0.18f;
            s1=ag_biquad_process(&d->filter_main, s1);
            s2=ag_biquad_process(&d->filter_mode2, s2);
            s3=ag_biquad_process(&d->filter_mode3, s3);
            float click = (s1*0.2f) ;
            click = ag_biquad_process(&d->hp_click, click);
            /* ripple is low sine */
            float ripple = sinf((float)(d->timer * d->ripple_freq * 2.0 * AG_PI * 0.5)) * env2 * 0.15f;
            out = (s1*0.7f + s2*0.4f + s3*0.25f)*env + click*env*0.3f + ripple;
            out *= d->gain;
            /* early reflection simulation: 15ms delay */
            int delay_samples = (int)(d->sr * 0.015);
            if(delay_samples>=64) delay_samples=63;
            float early = d->early_delay[(d->early_pos - delay_samples + 64)%64] * 0.25f;
            d->early_delay[d->early_pos]=out;
            d->early_pos=(d->early_pos+1)%64;
            out += early;
        }
    }
    /* slight stereo from early */
    *out_l = out * 0.6f;
    *out_r = out * 0.4f;
}
void ag_drip_auto(AgDrip *d, float density) {
    if(d->timer >= d->next_drip_time){
        d->timer=0;
        float interval = ag_rng_range_f32(&d->rng, 0.25f, 2.2f) / (density>0.01f?density:0.01f);
        d->next_drip_time=interval;
        float freq=ag_rng_range_f32(&d->rng, 850, 2600);
        float gain=ag_rng_range_f32(&d->rng, 0.35f, 0.85f);
        ag_drip_trigger(d,freq,gain);
    }
}

/* ---------- Bubbles HQ ---------- */
void ag_bubbles_init(AgBubbles *b, double sr) {
    memset(b,0,sizeof(*b));
    b->sr=sr>0?sr:AG_SR_DEFAULT;
    b->gain=0.55f;
    b->rate=3.0f;
    b->size_var=0.5f;
    ag_rng_seed(&b->rng, 0xB0B);
    for(int i=0;i<AG_BUBBLES_MAX_VOICES;i++){
        ag_osc_init(&b->voices[i].osc, AG_OSC_SINE, sr);
        AgADSR adsr = {0.005f,0.22f,0.0f,0.06f,1,1,1,0,0};
        ag_env_init(&b->voices[i].env, adsr, sr);
        ag_biquad_init(&b->voices[i].formant);
        ag_osc_init(&b->voices[i].wobble_lfo, AG_OSC_SINE, sr);
        b->voices[i].active=0;
    }
    b->next_bubble=0.25;
}
void ag_bubbles_set_rate(AgBubbles *b, float rate){ b->rate=ag_clamp_f(rate,0.1f,20.0f); }
static void bubble_trigger(AgBubbles *b, int idx) {
    AgBubbleVoice *v=&b->voices[idx];
    float base_freq = ag_rng_range_f32(&b->rng, 280, 1300);
    float size = ag_rng_range_f32(&b->rng, 0.7f, 1.4f);
    float freq = base_freq / size;
    float target = freq * ag_rng_range_f32(&b->rng, 1.4f, 2.2f); /* rising */
    v->freq=freq;
    v->target_freq=target;
    v->gain=ag_rng_range_f32(&b->rng, 0.25f, 0.7f) * (0.6f + size*0.3f);
    ag_osc_set_freq(&v->osc, freq);
    ag_biquad_set(&v->formant, AG_FILTER_BP, freq*1.8f, 1.5f, 0, (float)b->sr);
    ag_osc_set_freq(&v->wobble_lfo, ag_rng_range_f32(&b->rng, 8.0f, 18.0f));
    float attack = 0.003f + (1.0f/size)*0.004f;
    float decay = 0.15f + size*0.15f;
    AgADSR adsr = {attack,decay,0.0f,0.05f,1,1,1,0,0};
    ag_env_init(&v->env, adsr, b->sr);
    ag_env_trigger(&v->env);
    v->active=1;
    v->age=0;
}
float ag_bubbles_next(AgBubbles *b) {
    float l,r; ag_bubbles_next_stereo(b,&l,&r); return (l+r)*0.5f;
}
void ag_bubbles_next_stereo(AgBubbles *b, float *out_l, float *out_r) {
    b->timer+=1.0/b->sr;
    if(b->timer >= b->next_bubble){
        b->timer=0;
        b->next_bubble=ag_rng_range_f32(&b->rng, 0.08f, 0.65f) / (b->rate*0.35f+0.15f);
        /* find free voice */
        for(int i=0;i<AG_BUBBLES_MAX_VOICES;i++){
            if(!b->voices[i].active){ bubble_trigger(b,i); break; }
        }
    }
    float ml=0,mr=0;
    for(int i=0;i<AG_BUBBLES_MAX_VOICES;i++){
        AgBubbleVoice *v=&b->voices[i];
        if(!v->active) continue;
        v->age+=1.0/b->sr;
        float env=ag_env_next(&v->env);
        if(ag_env_is_idle(&v->env) || env<0.001f){ v->active=0; continue; }
        /* rising pitch */
        float t = (float)(v->age * 3.0); /* speed of rise */
        if(t>1) t=1;
        float freq = v->freq + (v->target_freq - v->freq) * t;
        /* wobble */
        float wob = ag_osc_next(&v->wobble_lfo) * freq * 0.03f;
        ag_osc_set_freq(&v->osc, freq + wob);
        float s=ag_osc_next(&v->osc) * env * v->gain;
        s=ag_biquad_process(&v->formant, s);
        /* pan based on voice index + random */
        float pan = ((i*0.37f) - 0.5f) + ag_rng_range_f32(&b->rng, -0.1f,0.1f)*0.1f;
        pan = ag_clamp_f(pan,-1,1);
        float pl,pr; ag_buffer_pan_stereo(s, pan, &pl, &pr);
        ml+=pl; mr+=pr;
    }
    *out_l=ml*b->gain;
    *out_r=mr*b->gain;
}

/* ---------- Underwater HQ ---------- */
void ag_underwater_amb_init(AgUnderwaterAmbience *uw, double sr) {
    memset(uw,0,sizeof(*uw));
    uw->sr=sr>0?sr:AG_SR_DEFAULT;
    uw->gain=0.55f;
    uw->pressure=0.5f;
    ag_river_init(&uw->base, sr);
    uw->base.gain=0.55f;
    uw->base.turbulence=0.25f;
    ag_biquad_init(&uw->muffle_lp); ag_biquad_set(&uw->muffle_lp, AG_FILTER_LP, 650.0f, 0.85f, 0, (float)sr);
    ag_biquad_init(&uw->muffle_lp2);ag_biquad_set(&uw->muffle_lp2,AG_FILTER_LP,320.0f,0.7f,0,(float)sr);
    ag_osc_init(&uw->pressure_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&uw->pressure_lfo, 0.08f);
    ag_osc_init(&uw->pressure_lfo2, AG_OSC_SINE, sr); ag_osc_set_freq(&uw->pressure_lfo2, 0.13f); uw->pressure_lfo2.phase=0.4f;
    ag_osc_init(&uw->sway_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&uw->sway_lfo, 0.05f);
    ag_bubbles_init(&uw->bubbles, sr); uw->bubbles.rate=1.2f; uw->bubbles.gain=0.35f;
    ag_noise_init(&uw->rumble_noise, 0x1115);
    ag_biquad_init(&uw->rumble_lp); ag_biquad_set(&uw->rumble_lp, AG_FILTER_LP, 90.0f, 0.7f, 0, (float)sr);
}
float ag_underwater_amb_next(AgUnderwaterAmbience *uw) {
    float l,r; ag_underwater_amb_next_stereo(uw,&l,&r); return (l+r)*0.5f;
}
void ag_underwater_amb_next_stereo(AgUnderwaterAmbience *uw, float *out_l, float *out_r) {
    float bl,br;
    ag_river_next_stereo(&uw->base, &bl, &br);
    /* pressure modulation */
    float press1 = ag_osc_next(&uw->pressure_lfo);
    float press2 = ag_osc_next(&uw->pressure_lfo2);
    float sway = ag_osc_next(&uw->sway_lfo);
    float pressure = (press1*0.6f + press2*0.4f) * 0.25f + sway*0.1f;
    float fc1 = 550.0f + pressure*250.0f;
    float fc2 = 280.0f + pressure*120.0f;
    ag_biquad_set(&uw->muffle_lp, AG_FILTER_LP, fc1, 0.85f, 0, (float)uw->sr);
    ag_biquad_set(&uw->muffle_lp2, AG_FILTER_LP, fc2, 0.7f, 0, (float)uw->sr);

    bl = ag_biquad_process(&uw->muffle_lp, bl);
    br = ag_biquad_process(&uw->muffle_lp, br);
    bl = ag_biquad_process(&uw->muffle_lp2, bl);
    br = ag_biquad_process(&uw->muffle_lp2, br);

    /* rumble */
    float rumble = ag_noise_brown(&uw->rumble_noise)*0.5f;
    rumble = ag_biquad_process(&uw->rumble_lp, rumble);
    rumble *= 0.4f * (0.8f + press1*0.3f);

    /* bubbles */
    float bub_l,bub_r;
    ag_bubbles_next_stereo(&uw->bubbles, &bub_l, &bub_r);

    *out_l = (bl + rumble*0.5f + bub_l*0.6f) * uw->gain;
    *out_r = (br + rumble*0.5f + bub_r*0.6f) * uw->gain;
}

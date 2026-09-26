#include "ag_fire.h"
#include <string.h>
#include <math.h>

void ag_fire_init(AgFire *f, double sr) {
    memset(f,0,sizeof(*f));
    f->sr=sr>0?sr:AG_SR_DEFAULT;
    f->gain=0.55f;
    f->crackle_density=0.18f;
    f->base_intensity=0.65f;
    f->rumble_gain=0.35f;
    f->body_gain=0.6f;
    f->hiss_gain=0.18f;
    ag_noise_init(&f->noise_low, 0xF111E);
    ag_noise_init(&f->noise_mid, 0xF111F);
    ag_noise_init(&f->noise_high, 0xF1120);
    ag_noise_init(&f->noise_crackle, 0xF1121);
    ag_rng_seed(&f->rng, 0xF111E);
    ag_biquad_init(&f->lp_rumble); ag_biquad_set(&f->lp_rumble, AG_FILTER_LP, 180.0f, 0.7f, 0, (float)sr);
    ag_biquad_init(&f->lp_body);   ag_biquad_set(&f->lp_body, AG_FILTER_LP, 2200.0f, 0.68f, 0, (float)sr);
    ag_biquad_init(&f->lp_body2);  ag_biquad_set(&f->lp_body2, AG_FILTER_LP, 1200.0f, 0.7f, 0, (float)sr);
    ag_biquad_init(&f->hp_hiss);   ag_biquad_set(&f->hp_hiss, AG_FILTER_HP, 3000.0f, 0.7f, 0, (float)sr);
    ag_biquad_init(&f->bp_crackle);ag_biquad_set(&f->bp_crackle, AG_FILTER_BP, 900.0f, 1.4f, 0, (float)sr);
    ag_biquad_init(&f->bp_crackle2);ag_biquad_set(&f->bp_crackle2,AG_FILTER_BP, 3200.0f,1.2f,0,(float)sr);
    ag_biquad_init(&f->bp_lick);   ag_biquad_set(&f->bp_lick, AG_FILTER_BP, 600.0f, 0.9f, 0, (float)sr);
    ag_osc_init(&f->flicker_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&f->flicker_lfo, 8.2f);
    ag_osc_init(&f->flicker_lfo2, AG_OSC_SINE, sr); ag_osc_set_freq(&f->flicker_lfo2, 11.7f); f->flicker_lfo2.phase=0.33f;
    ag_osc_init(&f->flicker_lfo3, AG_OSC_SINE, sr); ag_osc_set_freq(&f->flicker_lfo3, 5.3f); f->flicker_lfo3.phase=0.71f;
    ag_osc_init(&f->lick_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&f->lick_lfo, 1.21f);
    ag_osc_init(&f->hiss_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&f->hiss_lfo, 14.3f);
    AgADSR adsr = {0.005f,0.12f,0.0f,0.08f,0.6f,1.2f,1.0f,0,0};
    ag_env_init(&f->lick_env, adsr, sr);
    f->next_lick=0.3;
}
void ag_fire_set(AgFire *f, float intensity, float crackle_density) {
    f->base_intensity=ag_clamp_f(intensity,0,1);
    f->crackle_density=ag_clamp_f(crackle_density,0,1);
    f->rumble_gain = 0.25f + intensity*0.25f;
    f->body_gain = 0.45f + intensity*0.35f;
    f->hiss_gain = 0.12f + intensity*0.18f;
}
float ag_fire_next(AgFire *f) {
    float l,r; ag_fire_next_stereo(f,&l,&r); return (l+r)*0.5f;
}
void ag_fire_next_stereo(AgFire *f, float *out_l, float *out_r) {
    /* LFOs */
    float flick1 = ag_osc_next(&f->flicker_lfo);
    float flick2 = ag_osc_next(&f->flicker_lfo2);
    float flick3 = ag_osc_next(&f->flicker_lfo3);
    float lick_mod = ag_osc_next(&f->lick_lfo);
    float hiss_mod = ag_osc_next(&f->hiss_lfo) * 0.15f;
    float flicker = (flick1*0.5f + flick2*0.3f + flick3*0.2f) * 0.18f;

    /* low rumble - brown noise */
    float low_n = ag_noise_brown(&f->noise_low)*0.7f + ag_noise_pink(&f->noise_low)*0.3f;
    low_n = ag_biquad_process(&f->lp_rumble, low_n);
    float low = low_n * f->rumble_gain * (0.75f + flick1*0.2f + f->base_intensity*0.3f);

    /* mid body - pink + white */
    float mid_n = ag_noise_pink(&f->noise_mid)*0.6f + ag_noise_white(&f->noise_mid)*0.25f + ag_noise_brown(&f->noise_mid)*0.15f;
    mid_n = ag_biquad_process(&f->lp_body, mid_n);
    float mid_mid = ag_biquad_process(&f->lp_body2, mid_n);
    float body = (mid_n*0.5f + mid_mid*0.5f) * f->body_gain * (0.8f + flicker + lick_mod*0.15f + f->base_intensity*0.35f);

    /* high hiss */
    float high_n = ag_noise_white(&f->noise_high)*0.6f + ag_noise_pink(&f->noise_high)*0.4f;
    high_n = ag_biquad_process(&f->hp_hiss, high_n);
    float hiss = high_n * f->hiss_gain * (0.6f + hiss_mod + flick2*0.15f);

    /* flame licks - occasional burst */
    f->lick_timer += 1.0/f->sr;
    float lick=0;
    if(f->lick_timer > f->next_lick){
        f->lick_timer=0;
        f->next_lick = ag_rng_range_f32(&f->rng, 0.15f, 0.6f) / (f->base_intensity*0.6f+0.4f);
        ag_env_trigger(&f->lick_env);
        float freq = ag_rng_range_f32(&f->rng, 400, 900);
        ag_biquad_set(&f->bp_lick, AG_FILTER_BP, freq, 1.0f, 0, (float)f->sr);
        f->lick_gain = ag_rng_range_f32(&f->rng, 0.3f, 0.9f);
    }
    float lick_env = ag_env_next(&f->lick_env);
    if(lick_env>0.001f){
        float ln = ag_noise_pink(&f->noise_mid)*0.5f + ag_noise_white(&f->noise_mid)*0.5f;
        ln = ag_biquad_process(&f->bp_lick, ln);
        lick = ln * lick_env * f->lick_gain * 0.6f;
    }

    /* crackle - velvet-like sharp transients with two bands */
    float crackle=0;
    if(ag_rng_next_f32(&f->rng) < f->crackle_density * 0.028f){
        float c = ag_noise_white(&f->noise_crackle) * 3.5f;
        c = c*c*c; /* sharp */
        float c1 = ag_biquad_process(&f->bp_crackle, c);
        float c2 = ag_biquad_process(&f->bp_crackle2, c*0.6f);
        crackle = (c1*0.7f + c2*0.5f) * ag_rng_range_f32(&f->rng, 0.5f, 1.0f);
    }
    /* second crackle layer - smaller */
    float crackle2=0;
    if(ag_rng_next_f32(&f->rng) < f->crackle_density * 0.045f){
        float c = ag_noise_white(&f->noise_crackle) * 2.0f;
        c = c*c;
        c = ag_biquad_process(&f->bp_crackle2, c);
        crackle2 = c * 0.4f;
    }

    /* stereo: low mono, body slightly stereo, hiss wide, crackle panned random */
    float crackle_pan = ag_rng_range_f32(&f->rng, -1,1) * 0.15f; /* subtle random, but use decor */
    f->decor += (ag_rng_next_f32(&f->rng)-0.5f)*0.002f;
    f->decor = ag_clamp_f(f->decor, -0.12f, 0.12f);
    float l = low*0.5f + body*0.55f + hiss*0.6f + lick*0.6f + crackle*0.6f;
    float r = low*0.5f + body*0.45f + hiss*0.4f + lick*0.4f + crackle*0.4f;
    l += crackle2*0.6f + hiss*0.12f + f->decor*0.05f;
    r += crackle2*0.4f - hiss*0.08f - f->decor*0.05f;
    l += crackle_pan*0.1f;
    r -= crackle_pan*0.1f;

    *out_l = l * f->gain;
    *out_r = r * f->gain;
}

/* Fireplace HQ */
void ag_fireplace_init(AgFireplace *fp, double sr) {
    memset(fp,0,sizeof(*fp));
    ag_fire_init(&fp->fire, sr);
    fp->fire.gain=0.45f;
    fp->fire.crackle_density=0.12f;
    ag_biquad_init(&fp->room_lp); ag_biquad_set(&fp->room_lp, AG_FILTER_LP, 1100.0f, 0.72f, 0, (float)sr);
    ag_biquad_init(&fp->room_lp2);ag_biquad_set(&fp->room_lp2,AG_FILTER_LP,320.0f,0.7f,0,(float)sr);
    ag_biquad_init(&fp->room_bp); ag_biquad_set(&fp->room_bp, AG_FILTER_BP, 250.0f, 0.9f, 0, (float)sr);
    ag_osc_init(&fp->room_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&fp->room_lfo, 0.21f);
    ag_osc_init(&fp->room_lfo2, AG_OSC_SINE, sr); ag_osc_set_freq(&fp->room_lfo2, 0.073f);
    fp->room_gain=0.32f;
    fp->room_mix=0.45f;
}
float ag_fireplace_next(AgFireplace *fp) {
    float l,r; ag_fireplace_next_stereo(fp,&l,&r); return (l+r)*0.5f;
}
void ag_fireplace_next_stereo(AgFireplace *fp, float *out_l, float *out_r) {
    float fl, fr;
    ag_fire_next_stereo(&fp->fire, &fl, &fr);
    float room_lfo = ag_osc_next(&fp->room_lfo)*0.12f;
    float room_lfo2 = ag_osc_next(&fp->room_lfo2)*0.08f;
    float room_l = ag_biquad_process(&fp->room_lp, fl);
    float room_r = ag_biquad_process(&fp->room_lp, fr);
    room_l = ag_biquad_process(&fp->room_lp2, room_l);
    room_r = ag_biquad_process(&fp->room_lp2, room_r);
    float res_l = ag_biquad_process(&fp->room_bp, fl) * 0.25f;
    float res_r = ag_biquad_process(&fp->room_bp, fr) * 0.25f;
    float l = fl*(1.0f-fp->room_mix) + (room_l+res_l)*(fp->room_mix+room_lfo) * fp->room_gain*2.2f;
    float r = fr*(1.0f-fp->room_mix) + (room_r+res_r)*(fp->room_mix+room_lfo2) * fp->room_gain*2.2f;
    *out_l = l * 0.92f;
    *out_r = r * 0.92f;
}

/* Torch HQ */
void ag_torch_init(AgTorch *t, double sr) {
    memset(t,0,sizeof(*t));
    ag_fire_init(&t->fire, sr);
    t->fire.gain=0.38f;
    t->fire.crackle_density=0.09f;
    t->fire.base_intensity=0.6f;
    ag_osc_init(&t->wind_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&t->wind_lfo, 1.21f);
    ag_osc_init(&t->wind_lfo2, AG_OSC_SINE, sr); ag_osc_set_freq(&t->wind_lfo2, 0.83f); t->wind_lfo2.phase=0.5f;
    ag_biquad_init(&t->wind_bp); ag_biquad_set(&t->wind_bp, AG_FILTER_BP, 300.0f, 0.8f, 0, (float)sr);
    t->wind_amount=0.35f;
}
float ag_torch_next(AgTorch *t) {
    float l,r; ag_torch_next_stereo(t,&l,&r); return (l+r)*0.5f;
}
void ag_torch_next_stereo(AgTorch *t, float *out_l, float *out_r) {
    float fl, fr;
    ag_fire_next_stereo(&t->fire, &fl, &fr);
    float wind1 = ag_osc_next(&t->wind_lfo) * t->wind_amount;
    float wind2 = ag_osc_next(&t->wind_lfo2) * t->wind_amount * 0.6f;
    float wind = (wind1*0.6f + wind2*0.4f);
    /* wind modulates filter */
    float fc = 300.0f + wind*120.0f;
    ag_biquad_set(&t->wind_bp, AG_FILTER_BP, fc, 0.8f, 0, (float)t->fire.sr);
    float wind_filt_l = ag_biquad_process(&t->wind_bp, fl) * 0.15f;
    float wind_filt_r = ag_biquad_process(&t->wind_bp, fr) * 0.15f;
    float l = fl * (1.0f + wind*0.35f) + wind_filt_l;
    float r = fr * (1.0f + wind*0.25f) + wind_filt_r;
    *out_l=l; *out_r=r;
}

/* Bonfire HQ */
void ag_bonfire_init(AgBonfire *bf, double sr) {
    memset(bf,0,sizeof(*bf));
    ag_fire_init(&bf->fire, sr);
    bf->fire.gain=0.72f;
    bf->fire.base_intensity=0.85f;
    bf->fire.crackle_density=0.22f;
    ag_noise_init(&bf->low_rumble, 0xB011);
    ag_noise_init(&bf->mid_rumble, 0xB012);
    ag_biquad_init(&bf->rumble_lp); ag_biquad_set(&bf->rumble_lp, AG_FILTER_LP, 120.0f, 0.7f, 0, (float)sr);
    ag_biquad_init(&bf->rumble_lp2);ag_biquad_set(&bf->rumble_lp2,AG_FILTER_LP,60.0f,0.7f,0,(float)sr);
    ag_biquad_init(&bf->rumble_bp); ag_biquad_set(&bf->rumble_bp, AG_FILTER_BP, 80.0f, 0.9f, 0, (float)sr);
    ag_osc_init(&bf->rumble_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&bf->rumble_lfo, 0.15f);
    ag_osc_init(&bf->ember_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&bf->ember_lfo, 0.53f);
    bf->rumble_gain=0.45f;
    bf->ember_gain=0.2f;
}
float ag_bonfire_next(AgBonfire *bf) {
    float l,r; ag_bonfire_next_stereo(bf,&l,&r); return (l+r)*0.5f;
}
void ag_bonfire_next_stereo(AgBonfire *bf, float *out_l, float *out_r) {
    float fl, fr;
    ag_fire_next_stereo(&bf->fire, &fl, &fr);
    float rumble_lfo = ag_osc_next(&bf->rumble_lfo) * 0.3f;
    float ember_lfo = ag_osc_next(&bf->ember_lfo) * 0.2f;

    float low_n = ag_noise_brown(&bf->low_rumble)*0.6f + ag_noise_pink(&bf->low_rumble)*0.4f;
    low_n = ag_biquad_process(&bf->rumble_lp, low_n);
    low_n = ag_biquad_process(&bf->rumble_lp2, low_n);
    float low_bp = ag_biquad_process(&bf->rumble_bp, low_n) * 0.5f;
    float rumble = (low_n*0.7f + low_bp*0.5f) * bf->rumble_gain * (0.8f + rumble_lfo);

    float mid_n = ag_noise_pink(&bf->mid_rumble)*0.5f + ag_noise_brown(&bf->mid_rumble)*0.5f;
    mid_n = ag_biquad_process(&bf->rumble_lp, mid_n);
    float ember = mid_n * bf->ember_gain * (0.6f + ember_lfo);

    float l = fl*0.72f + rumble*0.55f + ember*0.6f;
    float r = fr*0.68f + rumble*0.45f + ember*0.4f;
    *out_l=l; *out_r=r;
}

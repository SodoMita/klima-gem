#include "ag_weather.h"
#include <string.h>
#include <math.h>

/* ---------- Rain HQ ---------- */
void ag_rain_sys_init(AgRainSystem *rs, double sr) {
    memset(rs,0,sizeof(*rs));
    rs->sr=sr>0?sr:AG_SR_DEFAULT;
    rs->gain=0.55f;
    rs->density=0.32f;
    rs->intensity=0.5f;
    rs->type=AG_WEATHER_RAIN_MEDIUM;
    rs->roof_gain=0.25f;
    rs->ground_gain=0.18f;
    ag_noise_init(&rs->noise_drizzle, 0xA11A);
    ag_noise_init(&rs->noise_drops, 0xA11B);
    ag_noise_init(&rs->noise_splash, 0xA11C);
    ag_rng_seed(&rs->rng, 0xA11A);
    ag_biquad_init(&rs->lp_drizzle); ag_biquad_set(&rs->lp_drizzle, AG_FILTER_LP, 4200.0f, 0.68f, 0, (float)sr);
    ag_biquad_init(&rs->hp_drizzle); ag_biquad_set(&rs->hp_drizzle, AG_FILTER_HP, 850.0f, 0.7f, 0, (float)sr);
    ag_biquad_init(&rs->lp_splash);  ag_biquad_set(&rs->lp_splash, AG_FILTER_LP, 1600.0f, 0.7f, 0, (float)sr);
    ag_biquad_init(&rs->bp_drop);    ag_biquad_set(&rs->bp_drop, AG_FILTER_BP, 2600.0f, 1.6f, 0, (float)sr);
    ag_biquad_init(&rs->bp_drop2);   ag_biquad_set(&rs->bp_drop2,AG_FILTER_BP, 5200.0f,1.2f,0,(float)sr);
    ag_osc_init(&rs->drizzle_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&rs->drizzle_lfo, 0.31f);
    for(int i=0;i<AG_RAIN_MAX_DROPS;i++){
        AgADSR adsr = {0.001f,0.04f,0.0f,0.02f,0.8f,1.2f,1.0f,0,0};
        ag_env_init(&rs->drops[i].env, adsr, sr);
        ag_biquad_init(&rs->drops[i].bp);
        rs->drops[i].active=0;
    }
}
void ag_rain_sys_set(AgRainSystem *rs, AgWeatherType type, float intensity) {
    rs->type=type;
    rs->intensity=ag_clamp_f(intensity,0,1);
    switch(type){
        case AG_WEATHER_RAIN_LIGHT: rs->density=0.18f; rs->gain=0.28f; rs->roof_gain=0.18f; break;
        case AG_WEATHER_RAIN_MEDIUM: rs->density=0.38f; rs->gain=0.48f; rs->roof_gain=0.28f; break;
        case AG_WEATHER_RAIN_HEAVY: rs->density=0.78f; rs->gain=0.72f; rs->roof_gain=0.42f; break;
        case AG_WEATHER_THUNDERSTORM: rs->density=0.65f; rs->gain=0.62f; rs->roof_gain=0.35f; break;
        case AG_WEATHER_HAIL: rs->density=0.55f; rs->gain=0.65f; rs->roof_gain=0.5f; break;
        case AG_WEATHER_SNOW_LIGHT: rs->density=0.12f; rs->gain=0.18f; rs->roof_gain=0.08f; break;
        case AG_WEATHER_SNOW_HEAVY: rs->density=0.28f; rs->gain=0.32f; rs->roof_gain=0.15f; break;
        case AG_WEATHER_FOG: rs->density=0.05f; rs->gain=0.12f; rs->roof_gain=0.05f; break;
        default: rs->density=0.0f; rs->gain=0.0f; rs->roof_gain=0.0f; break;
    }
    rs->gain *= (0.55f + rs->intensity*0.55f);
    rs->ground_gain = rs->gain * 0.35f;
}
static void rain_trigger_drop(AgRainSystem *rs) {
    for(int i=0;i<AG_RAIN_MAX_DROPS;i++){
        if(!rs->drops[i].active){
            float freq = ag_rng_range_f32(&rs->rng, 1600, 6200);
            if(rs->type==AG_WEATHER_HAIL) freq = ag_rng_range_f32(&rs->rng, 2200, 8500);
            if(rs->type==AG_WEATHER_SNOW_LIGHT || rs->type==AG_WEATHER_SNOW_HEAVY) freq = ag_rng_range_f32(&rs->rng, 900, 2200);
            rs->drops[i].freq=freq;
            rs->drops[i].gain=ag_rng_range_f32(&rs->rng, 0.25f, 1.0f) * rs->intensity;
            rs->drops[i].pan=ag_rng_range_f32(&rs->rng, -1.0f, 1.0f);
            ag_biquad_set(&rs->drops[i].bp, AG_FILTER_BP, freq, 1.8f + ag_rng_next_f32(&rs->rng)*0.6f, 0, (float)rs->sr);
            float attack = ag_rng_range_f32(&rs->rng, 0.0005f, 0.002f);
            float decay = ag_rng_range_f32(&rs->rng, 0.02f, 0.06f);
            AgADSR adsr = {attack,decay,0.0f,0.015f,0.8f,1.2f,1.0f,0,0};
            ag_env_init(&rs->drops[i].env, adsr, rs->sr);
            ag_env_trigger(&rs->drops[i].env);
            rs->drops[i].active=1;
            break;
        }
    }
}
float ag_rain_sys_next(AgRainSystem *rs) {
    float l,r; ag_rain_sys_next_stereo(rs,&l,&r); return (l+r)*0.5f;
}
void ag_rain_sys_next_stereo(AgRainSystem *rs, float *out_l, float *out_r) {
    if(rs->density<=0.001f){ *out_l=0; *out_r=0; return; }

    float drizzle_lfo = ag_osc_next(&rs->drizzle_lfo) * 0.18f;

    /* continuous drizzle - filtered noise */
    float drizzle_n = ag_noise_white(&rs->noise_drizzle)*0.35f + ag_noise_pink(&rs->noise_drizzle)*0.4f + ag_noise_brown(&rs->noise_drizzle)*0.15f;
    drizzle_n = ag_biquad_process(&rs->lp_drizzle, drizzle_n);
    drizzle_n = ag_biquad_process(&rs->hp_drizzle, drizzle_n);
    float drizzle = drizzle_n * 0.08f * rs->intensity * (0.7f + drizzle_lfo);

    /* roof patter - slightly filtered */
    float roof = drizzle * rs->roof_gain * 0.8f;

    /* ground splash - low */
    rs->splash_timer+=1.0/rs->sr;
    float splash=0;
    if(rs->splash_timer > 0.12f){
        rs->splash_timer=0;
        if(ag_rng_next_f32(&rs->rng) < rs->density*0.25f){
            float s = ag_noise_white(&rs->noise_splash)*0.5f;
            s = ag_biquad_process(&rs->lp_splash, s);
            splash = s * rs->ground_gain * ag_rng_range_f32(&rs->rng, 0.3f, 0.9f);
        }
    }

    /* drops */
    rs->drip_timer+=1.0/rs->sr;
    if(rs->drip_timer > 0.006){
        rs->drip_timer=0;
        if(ag_rng_next_f32(&rs->rng) < rs->density*0.22f){
            rain_trigger_drop(rs);
        }
    }

    float drops_l=0, drops_r=0;
    for(int i=0;i<AG_RAIN_MAX_DROPS;i++){
        if(!rs->drops[i].active) continue;
        float env = ag_env_next(&rs->drops[i].env);
        if(env<0.001f || ag_env_is_idle(&rs->drops[i].env)){ rs->drops[i].active=0; continue; }
        float n = ag_noise_white(&rs->noise_drops) * rs->drops[i].gain * env;
        n = ag_biquad_process(&rs->drops[i].bp, n);
        /* second harmonic for hardness */
        float n2 = ag_biquad_process(&rs->bp_drop2, n*0.5f);
        float s = n*0.75f + n2*0.35f;
        float pl,pr; ag_buffer_pan_stereo(s, rs->drops[i].pan, &pl, &pr);
        drops_l+=pl; drops_r+=pr;
    }

    /* stereo mix: drizzle mostly mono with slight width, drops panned */
    float l = drizzle*0.5f + roof*0.4f + splash*0.5f + drops_l*0.9f;
    float r = drizzle*0.5f + roof*0.35f + splash*0.5f + drops_r*0.9f;
    /* add width */
    l += drizzle*0.08f;
    r -= drizzle*0.05f;

    *out_l = l * rs->gain;
    *out_r = r * rs->gain;
}

/* ---------- Thunder HQ ---------- */
void ag_thunder_init(AgThunder *th, double sr) {
    memset(th,0,sizeof(*th));
    th->sr=sr>0?sr:AG_SR_DEFAULT;
    th->gain=0.85f;
    th->distance=0.5f;
    th->roll_gain=0.35f;
    ag_noise_init(&th->noise_crack, 0x7414);
    ag_noise_init(&th->noise_rumble, 0x7415);
    ag_biquad_init(&th->lp_crack); ag_biquad_set(&th->lp_crack, AG_FILTER_LP, 280.0f, 0.72f, 0, (float)sr);
    ag_biquad_init(&th->bp_crack); ag_biquad_set(&th->bp_crack, AG_FILTER_BP, 95.0f, 1.1f, 0, (float)sr);
    ag_biquad_init(&th->lp_rumble);ag_biquad_set(&th->lp_rumble,AG_FILTER_LP,180.0f,0.7f,0,(float)sr);
    ag_biquad_init(&th->lp_rumble2);ag_biquad_set(&th->lp_rumble2,AG_FILTER_LP,75.0f,0.7f,0,(float)sr);
    ag_biquad_init(&th->hp_crack); ag_biquad_set(&th->hp_crack, AG_FILTER_HP, 35.0f,0.7f,0,(float)sr);
    ag_osc_init(&th->rumble_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&th->rumble_lfo, 0.08f);
    ag_osc_init(&th->rumble_lfo2, AG_OSC_SINE, sr); ag_osc_set_freq(&th->rumble_lfo2, 0.13f); th->rumble_lfo2.phase=0.4f;
    ag_osc_init(&th->roll_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&th->roll_lfo, 1.47f);
    ag_rng_seed(&th->rng, 0x7414);
    th->next_thunder=ag_rng_range_f32(&th->rng, 4.0f, 9.0f);
    AgADSR adsr_crack = {0.008f,0.35f,0.0f,0.25f,1,1,1,0,0};
    ag_env_init(&th->env_crack, adsr_crack, sr);
    AgADSR adsr_rumble = {0.12f,2.2f,0.0f,1.2f,1,1,1,0,0};
    ag_env_init(&th->env_rumble, adsr_rumble, sr);
    for(int i=0;i<AG_THUNDER_MAX_ECHOES;i++) th->echoes[i].active=0;
}
void ag_thunder_trigger(AgThunder *th) {
    ag_thunder_trigger_with_distance(th, ag_rng_range_f32(&th->rng, 0.1f, 0.9f));
}
void ag_thunder_trigger_with_distance(AgThunder *th, float distance) {
    th->distance=ag_clamp_f(distance,0,1);
    ag_env_trigger(&th->env_crack);
    ag_env_trigger(&th->env_rumble);
    th->active=1;
    th->active_time=0;
    th->active_dur=ag_rng_range_f32(&th->rng, 1.2f, 3.5f) * (0.7f + th->distance*0.6f);
    /* setup echoes: more and longer for far thunder */
    int num_echoes = th->distance > 0.5f ? 4 : 2;
    for(int i=0;i<num_echoes && i<AG_THUNDER_MAX_ECHOES;i++){
        th->echoes[i].delay = ag_rng_range_f32(&th->rng, 0.3f, 1.2f) * (i+1) * (0.8f + th->distance*0.5f);
        th->echoes[i].gain = ag_rng_range_f32(&th->rng, 0.25f, 0.55f) / (i+1) * (0.6f + th->distance*0.4f);
        th->echoes[i].lpf = 200.0f - th->distance*80.0f - i*20.0f;
        if(th->echoes[i].lpf<40) th->echoes[i].lpf=40;
        th->echoes[i].timer=0;
        th->echoes[i].active=1;
    }
    for(int i=num_echoes;i<AG_THUNDER_MAX_ECHOES;i++) th->echoes[i].active=0;
    /* adjust filters based on distance: close = more high freq, far = more low */
    float crack_lp = 320.0f - th->distance*140.0f;
    float rumble_lp = 200.0f - th->distance*50.0f;
    ag_biquad_set(&th->lp_crack, AG_FILTER_LP, crack_lp, 0.72f, 0, (float)th->sr);
    ag_biquad_set(&th->lp_rumble, AG_FILTER_LP, rumble_lp, 0.7f, 0, (float)th->sr);
}
float ag_thunder_next(AgThunder *th) {
    float l,r; ag_thunder_next_stereo(th,&l,&r); return (l+r)*0.5f;
}
void ag_thunder_next_stereo(AgThunder *th, float *out_l, float *out_r) {
    th->timer+=1.0/th->sr;
    if(th->active){
        th->active_time+=1.0/th->sr;
        if(th->active_time >= th->active_dur){
            /* check echoes still active */
            int any_echo=0;
            for(int i=0;i<AG_THUNDER_MAX_ECHOES;i++) if(th->echoes[i].active) any_echo=1;
            if(!any_echo) th->active=0;
        }
    }
    if(!th->active){ *out_l=0; *out_r=0; return; }

    float env_crack = ag_env_next(&th->env_crack);
    float env_rumble = ag_env_next(&th->env_rumble);
    if(ag_env_is_idle(&th->env_crack) && ag_env_is_idle(&th->env_rumble) && th->active_time>0.5) {
        /* keep active for echoes */
        env_crack*=0.1f; env_rumble*=0.3f;
    }

    /* crack - sharp transient + bandpassed */
    float crack_n = ag_noise_white(&th->noise_crack)*0.7f + ag_noise_pink(&th->noise_crack)*0.3f;
    crack_n = ag_biquad_process(&th->lp_crack, crack_n);
    crack_n = ag_biquad_process(&th->bp_crack, crack_n);
    crack_n = ag_biquad_process(&th->hp_crack, crack_n);
    /* add high crack for close thunder */
    float close_crack=0;
    if(th->distance < 0.4f){
        float hc = ag_noise_white(&th->noise_crack)*0.4f;
        /* quick HP for snap */
        close_crack = hc * env_crack * 0.6f * (1.0f - th->distance*2.0f);
    }
    float crack = crack_n * env_crack * 1.4f + close_crack;

    /* rumble - brown noise with LFO */
    float rumble_n = ag_noise_brown(&th->noise_rumble)*0.65f + ag_noise_pink(&th->noise_rumble)*0.35f;
    rumble_n = ag_biquad_process(&th->lp_rumble, rumble_n);
    rumble_n = ag_biquad_process(&th->lp_rumble2, rumble_n);
    float rumble_lfo1 = ag_osc_next(&th->rumble_lfo) * 0.35f;
    float rumble_lfo2 = ag_osc_next(&th->rumble_lfo2) * 0.2f;
    float roll = ag_osc_next(&th->roll_lfo) * th->roll_gain;
    float rumble = rumble_n * env_rumble * (1.0f + rumble_lfo1 + rumble_lfo2 + roll*0.3f) * 1.3f;

    float base = crack*0.8f + rumble*0.9f;

    /* echoes */
    float echo_sum=0;
    for(int i=0;i<AG_THUNDER_MAX_ECHOES;i++){
        if(!th->echoes[i].active) continue;
        th->echoes[i].timer+=1.0/th->sr;
        if(th->echoes[i].timer >= th->echoes[i].delay){
            /* echo is delayed rumble with filtering */
            float echo_env = expf(-(float)(th->echoes[i].timer - th->echoes[i].delay)*0.6f);
            if(echo_env<0.01f){ th->echoes[i].active=0; continue; }
            float en = ag_noise_brown(&th->noise_rumble)*0.5f;
            /* simple LP per echo via gain */
            echo_sum += en * echo_env * th->echoes[i].gain * 0.7f;
        }
    }

    float mono = base + echo_sum*0.6f;

    /* stereo: close thunder more mono, far more wide with echoes */
    float width = 0.2f + th->distance*0.5f;
    float l = mono * (0.5f + width*0.1f) + echo_sum*0.15f;
    float r = mono * (0.5f - width*0.05f) + echo_sum*0.1f;
    /* add slight decorrelation */
    l += rumble*0.08f;
    r += crack*0.05f;

    *out_l = l * th->gain;
    *out_r = r * th->gain;
}
void ag_thunder_auto(AgThunder *th, float storm_intensity) {
    if(th->timer >= th->next_thunder){
        th->timer=0;
        th->next_thunder = ag_rng_range_f32(&th->rng, 3.5f, 14.0f) / (storm_intensity>0.01f?storm_intensity:0.01f);
        if(ag_rng_next_f32(&th->rng) < storm_intensity*0.55f){
            float dist = ag_rng_range_f32(&th->rng, 0.15f, 0.85f);
            ag_thunder_trigger_with_distance(th, dist);
        }
    }
}

/* ---------- Wind HQ ---------- */
void ag_wind_sys_init(AgWindSystem *ws, double sr) {
    memset(ws,0,sizeof(*ws));
    ws->sr=sr>0?sr:AG_SR_DEFAULT;
    ws->gain=0.52f;
    ws->base_strength=0.32f;
    ws->gust_strength=0.35f;
    ws->turbulence=0.25f;
    ws->howl_amount=0.2f;
    ag_noise_init(&ws->noise_base, 0x1111);
    ag_noise_init(&ws->noise_gust, 0x1112);
    ag_noise_init(&ws->noise_turb, 0x1113);
    ag_noise_init(&ws->noise_howl, 0x1114);
    ag_biquad_init(&ws->lp_base); ag_biquad_set(&ws->lp_base, AG_FILTER_LP, 850.0f, 0.68f, 0, (float)sr);
    ag_biquad_init(&ws->lp_base2);ag_biquad_set(&ws->lp_base2,AG_FILTER_LP,420.0f,0.7f,0,(float)sr);
    ag_biquad_init(&ws->lp_gust); ag_biquad_set(&ws->lp_gust, AG_FILTER_LP, 260.0f, 0.7f, 0, (float)sr);
    ag_biquad_init(&ws->bp_howl); ag_biquad_set(&ws->bp_howl, AG_FILTER_BP, 450.0f, 1.8f, 0, (float)sr);
    ag_biquad_init(&ws->hp_turb); ag_biquad_set(&ws->hp_turb, AG_FILTER_HP, 1200.0f, 0.7f, 0, (float)sr);
    ag_osc_init(&ws->gust_lfo1, AG_OSC_SINE, sr); ag_osc_set_freq(&ws->gust_lfo1, 0.11f);
    ag_osc_init(&ws->gust_lfo2, AG_OSC_SINE, sr); ag_osc_set_freq(&ws->gust_lfo2, 0.23f); ws->gust_lfo2.phase=0.37f;
    ag_osc_init(&ws->gust_env_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&ws->gust_env_lfo, 0.071f);
    ag_osc_init(&ws->turbulence_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&ws->turbulence_lfo, 1.53f);
    ag_osc_init(&ws->howl_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&ws->howl_lfo, 0.31f);
    ag_osc_init(&ws->sway_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&ws->sway_lfo, 0.051f);
    AgADSR adsr = {0.8f,1.5f,0.0f,1.2f,0.6f,1.2f,1.0f,0,0};
    ag_env_init(&ws->gust_env, adsr, sr);
    ag_rng_seed(&ws->rng, 0x1111);
    ws->next_gust=ag_rng_range_f32(&ws->rng, 2.0f, 5.0f);
}
void ag_wind_sys_set(AgWindSystem *ws, float base_strength, float gust_strength, float turbulence) {
    ws->base_strength=ag_clamp_f(base_strength,0,1);
    ws->gust_strength=ag_clamp_f(gust_strength,0,1);
    ws->turbulence=ag_clamp_f(turbulence,0,1);
    ws->howl_amount = ag_clamp_f(gust_strength*0.6f + turbulence*0.3f, 0, 1);
}
float ag_wind_sys_next(AgWindSystem *ws) {
    float l,r; ag_wind_sys_next_stereo(ws,&l,&r); return (l+r)*0.5f;
}
void ag_wind_sys_next_stereo(AgWindSystem *ws, float *out_l, float *out_r) {
    /* base wind - pink + brown */
    float base_n = ag_noise_pink(&ws->noise_base)*0.55f + ag_noise_brown(&ws->noise_base)*0.35f + ag_noise_white(&ws->noise_base)*0.1f;
    base_n = ag_biquad_process(&ws->lp_base, base_n);
    base_n = ag_biquad_process(&ws->lp_base2, base_n);

    /* gust handling */
    ws->gust_timer+=1.0/ws->sr;
    if(ws->gust_timer > ws->next_gust){
        ws->gust_timer=0;
        ws->next_gust = ag_rng_range_f32(&ws->rng, 2.5f, 7.0f) / (ws->gust_strength*0.5f+0.3f);
        if(ag_rng_next_f32(&ws->rng) < ws->gust_strength*0.7f + 0.15f){
            ag_env_trigger(&ws->gust_env);
            ws->gust_current = ag_rng_range_f32(&ws->rng, 0.4f, 1.0f) * ws->gust_strength;
        }
    }
    float gust_env = ag_env_next(&ws->gust_env);
    float gust_lfo1 = ag_osc_next(&ws->gust_lfo1);
    float gust_lfo2 = ag_osc_next(&ws->gust_lfo2);
    float gust_env_lfo = ag_osc_next(&ws->gust_env_lfo) * 0.25f;
    float gust_mod = (gust_lfo1*0.5f + gust_lfo2*0.3f + gust_env_lfo) * ws->gust_strength + gust_env*ws->gust_current;

    float gust_n = ag_noise_brown(&ws->noise_gust)*0.6f + ag_noise_pink(&ws->noise_gust)*0.4f;
    gust_n = ag_biquad_process(&ws->lp_gust, gust_n);
    float gust = gust_n * (ws->gust_strength*0.6f + gust_mod*0.5f);

    /* turbulence - high freq crackle */
    float turb_lfo = ag_osc_next(&ws->turbulence_lfo) * ws->turbulence;
    float turb_n = ag_noise_white(&ws->noise_turb)*0.6f + ag_noise_pink(&ws->noise_turb)*0.4f;
    turb_n = ag_biquad_process(&ws->hp_turb, turb_n);
    float turb = turb_n * ws->turbulence * (0.25f + turb_lfo*0.3f + gust_env*0.2f) * 0.35f;

    /* howl - resonant howling when windy */
    float howl_lfo = ag_osc_next(&ws->howl_lfo);
    float sway = ag_osc_next(&ws->sway_lfo) * 0.15f;
    float howl_fc = 350.0f + howl_lfo*180.0f + gust_mod*220.0f + sway*80.0f;
    howl_fc = ag_clamp_f(howl_fc, 200, 1200);
    ag_biquad_set(&ws->bp_howl, AG_FILTER_BP, howl_fc, 1.8f + ws->howl_amount*0.8f, 0, (float)ws->sr);
    float howl_n = ag_noise_white(&ws->noise_howl)*0.5f + ag_noise_pink(&ws->noise_howl)*0.5f;
    float howl = ag_biquad_process(&ws->bp_howl, howl_n) * ws->howl_amount * (0.25f + gust_env*0.5f + fabsf(howl_lfo)*0.2f);

    float base = base_n * (ws->base_strength*0.7f + 0.15f + gust_mod*0.25f);

    /* stereo: base mono, gust slightly stereo, turb wide, howl panned */
    float l = base*0.5f + gust*0.55f + turb*0.65f + howl*0.6f;
    float r = base*0.5f + gust*0.45f + turb*0.35f + howl*0.4f;
    /* sway adds stereo movement */
    l += sway*0.08f * base;
    r -= sway*0.06f * base;
    /* decorrelate high */
    l += turb*0.12f;
    r -= turb*0.08f;

    *out_l = l * ws->gain;
    *out_r = r * ws->gain;
}

/* ---------- Weather Mixer HQ ---------- */
void ag_weather_mixer_init(AgWeatherMixer *wm, double sr) {
    memset(wm,0,sizeof(*wm));
    wm->sr=sr>0?sr:AG_SR_DEFAULT;
    wm->gain=0.72f;
    wm->wind_gain=0.6f;
    wm->rain_gain=0.7f;
    wm->type=AG_WEATHER_CLEAR;
    wm->intensity=0.0f;
    ag_rain_sys_init(&wm->rain, sr);
    ag_thunder_init(&wm->thunder, sr);
    ag_wind_sys_init(&wm->wind, sr);
}
void ag_weather_mixer_set(AgWeatherMixer *wm, AgWeatherType type, float intensity) {
    wm->type=type;
    wm->intensity=ag_clamp_f(intensity,0,1);
    ag_rain_sys_set(&wm->rain, type, intensity);
    if(type==AG_WEATHER_THUNDERSTORM){
        ag_wind_sys_set(&wm->wind, 0.42f*intensity, 0.68f*intensity, 0.55f*intensity);
        wm->wind_gain=0.65f; wm->rain_gain=0.75f;
    } else if(type==AG_WEATHER_WINDY){
        ag_wind_sys_set(&wm->wind, 0.52f*intensity, 0.78f*intensity, 0.65f*intensity);
        wm->wind_gain=0.85f; wm->rain_gain=0.1f;
    } else if(type==AG_WEATHER_CLEAR){
        ag_wind_sys_set(&wm->wind, 0.06f, 0.06f, 0.06f);
        wm->wind_gain=0.3f; wm->rain_gain=0.0f;
    } else if(type==AG_WEATHER_FOG){
        ag_wind_sys_set(&wm->wind, 0.08f*intensity, 0.12f*intensity, 0.08f*intensity);
        wm->wind_gain=0.25f; wm->rain_gain=0.15f;
    } else {
        ag_wind_sys_set(&wm->wind, 0.12f*intensity, 0.22f*intensity, 0.12f*intensity);
        wm->wind_gain=0.45f; wm->rain_gain=0.7f;
    }
}
float ag_weather_mixer_next(AgWeatherMixer *wm) {
    float l,r; ag_weather_mixer_next_stereo(wm,&l,&r); return (l+r)*0.5f;
}
void ag_weather_mixer_next_stereo(AgWeatherMixer *wm, float *out_l, float *out_r) {
    float rain_l=0, rain_r=0;
    float wind_l=0, wind_r=0;
    float thunder_l=0, thunder_r=0;

    if(wm->type!=AG_WEATHER_CLEAR && wm->type!=AG_WEATHER_WINDY){
        ag_rain_sys_next_stereo(&wm->rain, &rain_l, &rain_r);
    }
    ag_wind_sys_next_stereo(&wm->wind, &wind_l, &wind_r);

    if(wm->type==AG_WEATHER_THUNDERSTORM){
        ag_thunder_auto(&wm->thunder, wm->intensity);
        ag_thunder_next_stereo(&wm->thunder, &thunder_l, &thunder_r);
    }

    float l = rain_l*wm->rain_gain + wind_l*wm->wind_gain + thunder_l*0.85f;
    float r = rain_r*wm->rain_gain + wind_r*wm->wind_gain + thunder_r*0.85f;

    *out_l = l * wm->gain;
    *out_r = r * wm->gain;
}

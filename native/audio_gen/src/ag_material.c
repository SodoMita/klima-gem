#include "ag_material.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>

/* ---------- Sand HQ ---------- */
void ag_sand_init(AgSand *s, double sr) {
    memset(s,0,sizeof(*s));
    s->sr = sr>0?sr:AG_SR_DEFAULT;
    s->gain=0.55f;
    s->density=0.35f;
    s->brightness=0.5f;
    ag_noise_init(&s->noise, 0x5A11D);
    ag_noise_init(&s->noise2, 0x5A11E);
    ag_rng_seed(&s->rng, 0x5A11D);
    ag_biquad_init(&s->lp); ag_biquad_set(&s->lp, AG_FILTER_LP, 4200,0.72f,0,(float)sr);
    ag_biquad_init(&s->hp); ag_biquad_set(&s->hp, AG_FILTER_HP, 180,0.7f,0,(float)sr);
    ag_biquad_init(&s->bp_mid); ag_biquad_set(&s->bp_mid, AG_FILTER_BP, 1800,0.9f,0,(float)sr);
    ag_biquad_init(&s->presence); ag_biquad_set(&s->presence, AG_FILTER_HISHELF, 3500,0.7f,3.0f,(float)sr);
    for(int i=0;i<AG_SAND_GRAINS;i++){
        s->grains[i].active=0;
        ag_biquad_init(&s->grains[i].bp);
        ag_biquad_set(&s->grains[i].bp, AG_FILTER_BP, 2500,1.2f,0,(float)sr);
    }
    s->grain_interval=0.02;
    AgADSR adsr = {0.001f,0.12f,0.0f,0.08f,0.8f,1.2f,1.0f,0,0};
    ag_env_init(&s->foot_env, adsr, sr);
    ag_biquad_init(&s->foot_lp); ag_biquad_set(&s->foot_lp, AG_FILTER_LP, 320,0.72f,0,(float)sr);
    ag_biquad_init(&s->foot_bp); ag_biquad_set(&s->foot_bp, AG_FILTER_BP, 900,1.1f,0,(float)sr);
    ag_dcblock_init(&s->dc);
}
void ag_sand_set(AgSand *s, float density, float brightness, float gain) {
    s->density=ag_clamp_f(density,0,1);
    s->brightness=ag_clamp_f(brightness,0,1);
    s->gain=ag_clamp_f(gain,0,2);
    float lp_fc = 2800 + brightness*4000;
    float hp_fc = 120 + (1-brightness)*180;
    ag_biquad_set(&s->lp, AG_FILTER_LP, lp_fc,0.72f,0,(float)s->sr);
    ag_biquad_set(&s->hp, AG_FILTER_HP, hp_fc,0.7f,0,(float)s->sr);
    ag_biquad_set(&s->presence, AG_FILTER_HISHELF, 3500+brightness*1500,0.7f, brightness*4.0f-1.0f, (float)s->sr);
}
static void sand_spawn_grain(AgSand *s) {
    for(int i=0;i<AG_SAND_GRAINS;i++){
        if(!s->grains[i].active){
            AgSandGrain *g=&s->grains[i];
            int len = (int)(s->sr * ag_rng_range_f32(&s->rng, 0.005f, 0.022f));
            if(len<32) len=32;
            if(len>AG_SAND_GRAIN_LEN) len=AG_SAND_GRAIN_LEN;
            g->len=len; g->pos=0;
            float freq = ag_rng_range_f32(&s->rng, 800, 6200) * (0.7f + s->brightness*0.8f);
            float q = ag_rng_range_f32(&s->rng, 0.8f, 2.2f);
            ag_biquad_set(&g->bp, AG_FILTER_BP, freq, q,0,(float)s->sr);
            for(int j=0;j<len;j++){
                float ph=(float)j/len;
                float win=0.5f-0.5f*cosf(ph*AG_TAU); /* Hann */
                float n = ag_noise_white(&s->noise)*0.6f + ag_noise_pink(&s->noise)*0.3f + ag_noise_brown(&s->noise2)*0.1f;
                n = ag_biquad_process(&g->bp, n);
                g->buf[j]=n*win;
            }
            g->gain=ag_rng_range_f32(&s->rng,0.18f,0.75f);
            float pan=ag_rng_range_f32(&s->rng,-1,1);
            ag_buffer_pan_stereo(1.0f, pan, &g->pan_l, &g->pan_r);
            g->active=1;
            return;
        }
    }
}
float ag_sand_next(AgSand *s) {
    float l,r; ag_sand_next_stereo(s,&l,&r); return (l+r)*0.5f;
}
void ag_sand_next_stereo(AgSand *s, float *out_l, float *out_r) {
    s->timer+=1.0/s->sr;
    if(s->timer>=s->grain_interval){
        s->timer=0;
        s->grain_interval= ag_rng_range_f32(&s->rng, 0.008f,0.035f) / (s->density*0.8f+0.2f);
        if(ag_rng_next_f32(&s->rng) < s->density) sand_spawn_grain(s);
        if(s->density>0.6f && ag_rng_next_f32(&s->rng)< (s->density-0.6f)*0.8f) sand_spawn_grain(s);
    }
    float ml=0,mr=0;
    for(int i=0;i<AG_SAND_GRAINS;i++){
        AgSandGrain *g=&s->grains[i];
        if(!g->active) continue;
        float sm=g->buf[g->pos];
        ml+=sm*g->pan_l*g->gain;
        mr+=sm*g->pan_r*g->gain;
        g->pos++;
        if(g->pos>=g->len) g->active=0;
    }
    /* continuous bed */
    float bed = ag_noise_white(&s->noise)*0.04f + ag_noise_pink(&s->noise2)*0.06f;
    bed = ag_biquad_process_hq(&s->hp, bed);
    bed = ag_biquad_process_hq(&s->lp, bed);
    bed = ag_biquad_process_hq(&s->bp_mid, bed*0.5f)*0.6f + bed*0.7f;
    bed = ag_biquad_process_hq(&s->presence, bed);
    bed *= s->density*0.35f;
    ml+=bed*0.6f; mr+=bed*0.4f;

    /* footstep */
    if(s->foot_active){
        float env=ag_env_next_hq(&s->foot_env);
        if(ag_env_is_idle(&s->foot_env)) s->foot_active=0;
        else {
            float thud = ag_noise_brown(&s->noise)*0.5f + ag_noise_pink(&s->noise)*0.3f;
            thud = ag_biquad_process_hq(&s->foot_lp, thud);
            thud = ag_biquad_process_hq(&s->foot_bp, thud*0.6f)*0.5f + thud*0.5f;
            float step = thud * env * s->foot_gain;
            ml+=step*0.55f; mr+=step*0.45f;
        }
    }

    ml = ag_dcblock_process(&s->dc, ml);
    mr = ag_dcblock_process(&s->dc, mr);
    ml = tanhf(ml*0.9f)*1.05f;
    mr = tanhf(mr*0.9f)*1.05f;
    *out_l=ml*s->gain;
    *out_r=mr*s->gain;
}
void ag_sand_footstep_trigger(AgSand *s, float vel) {
    s->foot_gain=ag_clamp_f(vel,0,1)*0.9f+0.1f;
    ag_env_trigger_vel(&s->foot_env, vel);
    s->foot_active=1;
}
void ag_sand_pour_trigger(AgSand *s, float intensity) {
    int count = (int)(intensity*8)+2;
    for(int i=0;i<count;i++) sand_spawn_grain(s);
}

/* ---------- Wood / Log HQ ---------- */
void ag_wood_init(AgWood *w, double sr) {
    memset(w,0,sizeof(*w));
    w->sr=sr>0?sr:AG_SR_DEFAULT;
    w->gain=0.62f;
    w->wood_tone=0.5f;
    for(int i=0;i<AG_WOOD_PARTIALS;i++){
        ag_osc_init(&w->partials[i], AG_OSC_SINE, sr);
        ag_biquad_init(&w->filters[i]);
        w->amps[i]=0;
        w->decays[i]=1;
        w->envs[i]=0;
    }
    ag_biquad_init(&w->body_lp); ag_biquad_set(&w->body_lp, AG_FILTER_LP, 3200,0.72f,0,(float)sr);
    ag_biquad_init(&w->body_hp); ag_biquad_set(&w->body_hp, AG_FILTER_HP, 40,0.7f,0,(float)sr);
    ag_biquad_init(&w->crack_hp); ag_biquad_set(&w->crack_hp, AG_FILTER_HP, 1800,0.7f,0,(float)sr);
    ag_noise_init(&w->crack_noise, 0x1117);
    ag_rng_seed(&w->rng, 0x1117);
    ag_dcblock_init(&w->dc);
    ag_osc_init(&w->creak_osc, AG_OSC_SINE, sr);
    ag_osc_init(&w->creak_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&w->creak_lfo, 0.35f);
    ag_biquad_init(&w->creak_filter); ag_biquad_set(&w->creak_filter, AG_FILTER_BP, 800,1.2f,0,(float)sr);
    AgADSR adsr = {0.02f,0.8f,0.0f,1.2f,0.4f,1.5f,1.0f,0,0};
    ag_env_init(&w->creak_env, adsr, sr);
}
void ag_wood_hit(AgWood *w, float freq, float vel, float hardness) {
    if(freq<20) freq=20;
    if(freq>3000) freq=3000;
    hardness=ag_clamp_f(hardness,0,1);
    w->wood_tone=hardness;
    float ratios[AG_WOOD_PARTIALS]={1.0f,2.03f,3.12f,4.27f,5.48f,7.02f};
    float amps[AG_WOOD_PARTIALS]={1.0f,0.58f,0.36f,0.22f,0.14f,0.08f};
    float decays[AG_WOOD_PARTIALS]={1.0f,0.72f,0.55f,0.42f,0.31f,0.21f};
    /* hardness makes higher partials louder and faster decay */
    for(int i=0;i<AG_WOOD_PARTIALS;i++){
        float f = freq*ratios[i] * (1.0f + ag_rng_range_f32(&w->rng,-0.003f,0.003f));
        ag_osc_set_freq(&w->partials[i], f);
        w->partials[i].phase=ag_rng_next_f32(&w->rng)*0.15f;
        float h_boost = 1.0f + hardness*0.6f*(i*0.25f);
        w->amps[i]=amps[i]*h_boost;
        w->decays[i]=decays[i]*(1.0f - hardness*0.25f) + 0.1f;
        w->envs[i]=1.0f;
        float q = 8.0f + i*2.0f + hardness*4.0f;
        ag_biquad_set(&w->filters[i], AG_FILTER_BP, f, q,0,(float)w->sr);
    }
    ag_biquad_set(&w->body_lp, AG_FILTER_LP, freq*4.5f+800,0.72f,0,(float)w->sr);
    ag_biquad_set(&w->body_hp, AG_FILTER_HP, 30,0.7f,0,(float)w->sr);
    ag_biquad_set(&w->crack_hp, AG_FILTER_HP, freq*1.2f+500,0.7f,0,(float)w->sr);
    w->active=1; w->t=0; w->vel=ag_clamp_f(vel,0,1);
}
float ag_wood_next(AgWood *w) {
    if(!w->active && !w->creak_active) return 0.0f;
    float out=0;
    if(w->active){
        w->t+=1.0/w->sr;
        int alive=0;
        for(int i=0;i<AG_WOOD_PARTIALS;i++){
            if(w->envs[i]<=0.0001f) continue;
            alive=1;
            w->envs[i]*=expf(-1.0f/(w->decays[i]*w->sr*0.6f)*2.8f);
            if(w->envs[i]<0.0001f) w->envs[i]=0;
            float s=ag_osc_next_hq(&w->partials[i]) * w->amps[i] * w->envs[i];
            s=ag_biquad_process_hq(&w->filters[i], s);
            out+=s;
        }
        /* crack transient */
        if(w->t<0.015){
            float crack = ag_noise_white(&w->crack_noise)*0.8f;
            crack=ag_biquad_process_hq(&w->crack_hp, crack);
            float crack_env = expf(-(float)w->t*220.0f);
            out+=crack*crack_env*0.35f*w->vel;
        }
        if(!alive) w->active=0;
        out=ag_biquad_process_hq(&w->body_lp, out);
        out=ag_biquad_process_hq(&w->body_hp, out);
    }
    /* creak layer */
    if(w->creak_active){
        float env=ag_env_next_hq(&w->creak_env);
        if(ag_env_is_idle(&w->creak_env)) w->creak_active=0;
        else {
            float lfo=ag_osc_next(&w->creak_lfo)*0.18f;
            float f = 120 + lfo*80 + env*200;
            ag_osc_set_freq(&w->creak_osc, f);
            float s=ag_osc_next_hq(&w->creak_osc)*env*0.5f;
            s=ag_biquad_process_hq(&w->creak_filter, s);
            /* add subtle noise */
            float n=ag_noise_pink(&w->crack_noise)*0.08f*env;
            out+=s+n;
        }
    }
    out=ag_dcblock_process(&w->dc, out);
    out=tanhf(out*0.88f)*1.08f;
    return out * w->gain * (0.7f + w->vel*0.5f) * 0.45f;
}
int ag_wood_active(const AgWood *w){ return w->active || w->creak_active; }
void ag_wood_creak_trigger(AgWood *w, float duration, float stress) {
    stress=ag_clamp_f(stress,0,1);
    ag_osc_set_freq(&w->creak_osc, 80+stress*120);
    ag_osc_set_freq(&w->creak_lfo, 0.2f+stress*0.8f);
    ag_biquad_set(&w->creak_filter, AG_FILTER_BP, 600+stress*900, 1.0f+stress*0.8f,0,(float)w->sr);
    AgADSR adsr={0.04f,duration*0.6f,0.0f,duration*0.4f,0.5f,1.2f,1.0f,0,0};
    ag_env_init(&w->creak_env, adsr, w->sr);
    ag_env_trigger(&w->creak_env);
    w->creak_active=1;
}

/* Log - deeper */
void ag_log_init(AgLog *l, double sr){ ag_wood_init(l,sr); l->gain=0.68f; }
void ag_log_hit(AgLog *l, float freq, float vel){
    if(freq>1200) freq=1200;
    ag_wood_hit(l, freq*0.65f, vel, 0.25f);
    /* more body */
    ag_biquad_set(&l->body_lp, AG_FILTER_LP, freq*2.2f+400,0.78f,0,(float)l->sr);
}
float ag_log_next(AgLog *l){ return ag_wood_next(l); }
void ag_log_creak_trigger(AgLog *l, float duration, float stress){ ag_wood_creak_trigger(l,duration*1.6f,stress*0.7f); }
int ag_log_active(const AgLog *l){ return ag_wood_active(l); }

/* ---------- Metal HQ ---------- */
void ag_metal_init(AgMetal *m, double sr) {
    memset(m,0,sizeof(*m));
    m->sr=sr>0?sr:AG_SR_DEFAULT;
    m->gain=0.58f;
    m->metallic=0.75f;
    for(int i=0;i<AG_METAL_PARTIALS;i++){
        ag_osc_init(&m->partials[i], AG_OSC_SINE, sr);
        ag_biquad_init(&m->filters[i]);
        m->amps[i]=0; m->decays[i]=1; m->envs[i]=0;
    }
    ag_biquad_init(&m->body_bp); ag_biquad_set(&m->body_bp, AG_FILTER_BP, 1200,1.0f,0,(float)sr);
    ag_biquad_init(&m->body_hp); ag_biquad_set(&m->body_hp, AG_FILTER_HP, 60,0.7f,0,(float)sr);
    ag_biquad_init(&m->scrape_bp); ag_biquad_set(&m->scrape_bp, AG_FILTER_BP, 2500,1.5f,0,(float)sr);
    ag_noise_init(&m->scrape_noise, 0x1E7A1);
    ag_osc_init(&m->scrape_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&m->scrape_lfo, 3.2f);
    ag_rng_seed(&m->rng, 0x1E7A1);
    ag_dcblock_init(&m->dc);
}
void ag_metal_hit(AgMetal *m, float freq, float vel, float metallic) {
    if(freq<30) freq=30;
    if(freq>4000) freq=4000;
    metallic=ag_clamp_f(metallic,0,1);
    m->metallic=metallic;
    /* inharmonic ratios for metal: not integer, bell-like but denser */
    float ratios[AG_METAL_PARTIALS]={1.0f,1.52f,2.14f,2.76f,3.48f,4.21f,5.33f,6.12f,7.44f,8.71f,10.12f,12.5f};
    float amps[AG_METAL_PARTIALS]={1.0f,0.72f,0.61f,0.52f,0.41f,0.33f,0.26f,0.20f,0.15f,0.11f,0.08f,0.05f};
    float decays[AG_METAL_PARTIALS]={1.0f,0.92f,0.85f,0.78f,0.71f,0.64f,0.56f,0.48f,0.40f,0.32f,0.24f,0.16f};
    for(int i=0;i<AG_METAL_PARTIALS;i++){
        float detune = ag_rng_range_f32(&m->rng, -0.006f,0.006f);
        float f = freq*ratios[i]*(1.0f+detune);
        ag_osc_set_freq(&m->partials[i], f);
        m->partials[i].phase=ag_rng_next_f32(&m->rng)*0.2f;
        float metal_boost = 1.0f + metallic*0.5f*(i>3?1:0);
        m->amps[i]=amps[i]*metal_boost;
        m->decays[i]=decays[i]*(0.7f+metallic*0.5f);
        m->envs[i]=1.0f;
        float q=12.0f + i*1.5f + metallic*6.0f;
        ag_biquad_set(&m->filters[i], AG_FILTER_BP, f, q,0,(float)m->sr);
    }
    ag_biquad_set(&m->body_bp, AG_FILTER_BP, freq*1.8f, 0.9f+metallic*0.5f,0,(float)m->sr);
    m->active=1; m->t=0; m->vel=ag_clamp_f(vel,0,1);
}
float ag_metal_next(AgMetal *m) {
    if(!m->active) return 0.0f;
    m->t+=1.0/m->sr;
    float out=0;
    int alive=0;
    for(int i=0;i<AG_METAL_PARTIALS;i++){
        if(m->envs[i]<=0.00008f) continue;
        alive=1;
        m->envs[i]*=expf(-1.0f/(m->decays[i]*m->sr*0.9f)*3.2f);
        if(m->envs[i]<0.00008f) m->envs[i]=0;
        float s=ag_osc_next_hq(&m->partials[i]) * m->amps[i] * m->envs[i];
        s=ag_biquad_process_hq(&m->filters[i], s);
        out+=s;
    }
    if(!alive) m->active=0;
    /* body resonance */
    float body=ag_biquad_process_hq(&m->body_bp, out*0.5f)*0.35f;
    out=out*0.75f + body;
    out=ag_biquad_process_hq(&m->body_hp, out);
    out=ag_dcblock_process(&m->dc, out);
    out=tanhf(out*0.85f)*1.12f;
    return out * m->gain * (0.6f + m->vel*0.6f) * 0.32f;
}
int ag_metal_active(const AgMetal *m){ return m->active; }
float ag_metal_scrape_next(AgMetal *m, float pressure) {
    pressure=ag_clamp_f(pressure,0,1);
    float lfo=ag_osc_next(&m->scrape_lfo)*0.25f;
    float fc = 1200 + pressure*3500 + lfo*600;
    ag_biquad_set(&m->scrape_bp, AG_FILTER_BP, fc, 1.2f+pressure*0.8f,0,(float)m->sr);
    float n = ag_noise_white(&m->scrape_noise)*0.5f + ag_noise_pink(&m->scrape_noise)*0.3f;
    float s=ag_biquad_process_hq(&m->scrape_bp, n);
    /* add metallic resonance */
    float metal_res=0;
    for(int i=0;i<3;i++){
        float f = fc * (1.0f + i*0.52f);
        ag_biquad_set(&m->filters[i], AG_FILTER_BP, f, 8.0f,0,(float)m->sr);
        metal_res+=ag_biquad_process_hq(&m->filters[i], n)*0.25f;
    }
    float out = s*0.6f + metal_res*0.4f;
    out=ag_dcblock_process(&m->dc, out);
    out=tanhf(out*0.9f)*1.05f;
    return out * pressure * m->gain * 0.5f;
}
void ag_metal_clang(AgMetal *m, float freq, float vel) {
    ag_metal_hit(m,freq,vel,0.95f);
    /* boost low partials for clang */
    for(int i=0;i<3;i++) m->amps[i]*=1.4f;
}

/* ---------- Stone ---------- */
void ag_stone_init(AgStone *s, double sr) {
    memset(s,0,sizeof(*s));
    ag_wood_init(&s->wood, sr);
    s->wood.gain=0.6f;
    ag_biquad_init(&s->hard_hp); ag_biquad_set(&s->hard_hp, AG_FILTER_HP, 2500,0.7f,0,(float)sr);
    ag_noise_init(&s->debris_noise, 0x510);
    ag_biquad_init(&s->debris_bp); ag_biquad_set(&s->debris_bp, AG_FILTER_BP, 3200,1.3f,0,(float)sr);
    AgADSR adsr={0.001f,0.18f,0.0f,0.08f,0.6f,1.2f,1.0f,0,0};
    ag_env_init(&s->debris_env, adsr, sr);
}
void ag_stone_hit(AgStone *s, float freq, float vel) {
    ag_wood_hit(&s->wood, freq, vel, 0.95f);
    /* make harder: faster decay, higher freq */
    for(int i=0;i<AG_WOOD_PARTIALS;i++){
        s->wood.decays[i]*=0.55f;
        s->wood.amps[i]*=(i>2?1.2f:0.9f);
    }
    ag_biquad_set(&s->hard_hp, AG_FILTER_HP, freq*0.8f+1200,0.7f,0,(float)s->wood.sr);
    ag_env_trigger_vel(&s->debris_env, vel);
}
float ag_stone_next(AgStone *s) {
    float base=ag_wood_next(&s->wood);
    float debris=0;
    float env=ag_env_next_hq(&s->debris_env);
    if(env>0.0001f){
        float n=ag_noise_white(&s->debris_noise)*0.7f;
        n=ag_biquad_process_hq(&s->debris_bp, n);
        n=ag_biquad_process_hq(&s->hard_hp, n);
        debris=n*env*0.4f;
    }
    return base*0.85f + debris;
}
int ag_stone_active(const AgStone *s){ return ag_wood_active(&s->wood) || !ag_env_is_idle(&s->debris_env); }

/* ---------- Glass ---------- */
void ag_glass_init(AgGlass *g, double sr) {
    memset(g,0,sizeof(*g));
    g->sr=sr>0?sr:AG_SR_DEFAULT;
    g->gain=0.55f;
    for(int i=0;i<AG_GLASS_PARTIALS;i++){
        ag_osc_init(&g->partials[i], AG_OSC_SINE, sr);
        ag_biquad_init(&g->filters[i]);
    }
    ag_biquad_init(&g->shimmer_lp); ag_biquad_set(&g->shimmer_lp, AG_FILTER_LP, 8000,0.7f,0,(float)sr);
    ag_dcblock_init(&g->dc);
    ag_rng_seed(&g->rng, 0x61A5);
}
void ag_glass_clink(AgGlass *g, float freq, float vel) {
    if(freq<400) freq=400;
    float ratios[AG_GLASS_PARTIALS]={1.0f,2.02f,3.01f,4.15f,5.23f,6.31f,8.02f,10.5f};
    float amps[AG_GLASS_PARTIALS]={1.0f,0.65f,0.42f,0.28f,0.18f,0.12f,0.07f,0.04f};
    float decays[AG_GLASS_PARTIALS]={1.0f,0.82f,0.68f,0.54f,0.42f,0.31f,0.21f,0.13f};
    for(int i=0;i<AG_GLASS_PARTIALS;i++){
        float f=freq*ratios[i]*(1.0f+ag_rng_range_f32(&g->rng,-0.0015f,0.0015f));
        ag_osc_set_freq(&g->partials[i], f);
        g->partials[i].phase=ag_rng_next_f32(&g->rng)*0.1f;
        g->amps[i]=amps[i];
        g->decays[i]=decays[i];
        g->envs[i]=1.0f;
        ag_biquad_set(&g->filters[i], AG_FILTER_BP, f, 15.0f+i*2.0f,0,(float)g->sr);
    }
    ag_biquad_set(&g->shimmer_lp, AG_FILTER_LP, freq*3.5f+2000,0.7f,0,(float)g->sr);
    g->active=1; g->t=0;
    g->gain=0.55f*ag_clamp_f(vel,0,1);
}
void ag_glass_shatter(AgGlass *g, float intensity) {
    intensity=ag_clamp_f(intensity,0,1);
    /* trigger many clinks quickly - for simplicity boost current */
    ag_glass_clink(g, ag_rng_range_f32(&g->rng, 800, 3500), intensity);
    for(int i=0;i<AG_GLASS_PARTIALS;i++){
        g->amps[i]*=(0.6f+intensity*0.8f);
        g->decays[i]*=(0.5f+intensity*0.3f);
    }
}
float ag_glass_next(AgGlass *g) {
    if(!g->active) return 0.0f;
    g->t+=1.0/g->sr;
    float out=0;
    int alive=0;
    for(int i=0;i<AG_GLASS_PARTIALS;i++){
        if(g->envs[i]<=0.00005f) continue;
        alive=1;
        g->envs[i]*=expf(-1.0f/(g->decays[i]*g->sr*0.7f)*4.0f);
        if(g->envs[i]<0.00005f) g->envs[i]=0;
        float s=ag_osc_next_hq(&g->partials[i]) * g->amps[i] * g->envs[i];
        s=ag_biquad_process_hq(&g->filters[i], s);
        out+=s;
    }
    if(!alive) g->active=0;
    out=ag_biquad_process_hq(&g->shimmer_lp, out);
    out=ag_dcblock_process(&g->dc, out);
    out=tanhf(out*0.85f)*1.1f;
    return out * g->gain * 0.38f;
}
int ag_glass_active(const AgGlass *g){ return g->active; }

/* ---------- Shimmer Pro ---------- */
void ag_shimmer_pro_init(AgShimmerPro *sh, double sr, float shift) {
    memset(sh,0,sizeof(*sh));
    sh->sr=sr>0?sr:AG_SR_DEFAULT;
    sh->gain=0.52f;
    sh->feedback=0.62f;
    sh->shift=shift>0.1f?shift:2.0f;
    sh->shimmer_mix=0.45f;
    sh->damping=0.35f;
    sh->buf_size = (int)(sr*2.0); /* 2 sec */
    if(sh->buf_size<44100) sh->buf_size=44100;
    if(sh->buf_size>AG_SHIMMER_PRO_BUF) sh->buf_size=AG_SHIMMER_PRO_BUF;
    sh->buf=(float*)calloc(sh->buf_size, sizeof(float));
    sh->owned=1;
    sh->write_pos=0;
    sh->read_pos=0;
    ag_biquad_init(&sh->lp); ag_biquad_set(&sh->lp, AG_FILTER_LP, 3200,0.72f,0,(float)sr);
    ag_biquad_init(&sh->hp); ag_biquad_set(&sh->hp, AG_FILTER_HP, 120,0.7f,0,(float)sr);
    ag_biquad_init(&sh->presence); ag_biquad_set(&sh->presence, AG_FILTER_HISHELF, 2500,0.7f,2.0f,(float)sr);
    ag_biquad_init(&sh->input_hp); ag_biquad_set(&sh->input_hp, AG_FILTER_HP, 80,0.7f,0,(float)sr);
    ag_dcblock_init(&sh->dc);
    ag_reverb_init(&sh->reverb, (int)sr);
    ag_reverb_set_wet(&sh->reverb, 0.35f);
    ag_reverb_set_dry(&sh->reverb, 0.65f);
    ag_reverb_set_room_size(&sh->reverb, 0.75f);
    ag_reverb_set_damping(&sh->reverb, 0.45f);
    ag_osc_init(&sh->lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&sh->lfo, 0.12f);
}
void ag_shimmer_pro_free(AgShimmerPro *sh) {
    if(sh->owned && sh->buf) free(sh->buf);
    memset(sh,0,sizeof(*sh));
}
void ag_shimmer_pro_set(AgShimmerPro *sh, float feedback, float mix, float damping) {
    sh->feedback=ag_clamp_f(feedback,0,0.92f);
    sh->shimmer_mix=ag_clamp_f(mix,0,1);
    sh->damping=ag_clamp_f(damping,0,1);
    ag_biquad_set(&sh->lp, AG_FILTER_LP, 1800 + (1.0f-damping)*4000,0.72f,0,(float)sh->sr);
}
float ag_shimmer_pro_process(AgShimmerPro *sh, float in) {
    float l,r; ag_shimmer_pro_process_stereo(sh,in,in,&l,&r); return (l+r)*0.5f;
}
void ag_shimmer_pro_process_stereo(AgShimmerPro *sh, float in_l, float in_r, float *out_l, float *out_r) {
    if(!sh->buf) { *out_l=in_l*sh->gain; *out_r=in_r*sh->gain; return; }
    float in = (in_l+in_r)*0.5f;
    in = ag_biquad_process_hq(&sh->input_hp, in);
    float delayed = sh->buf[sh->write_pos];
    float lfo = ag_osc_next(&sh->lfo)*0.06f;
    float fb = sh->feedback * (0.92f + lfo);
    float to_write = in*0.35f + delayed*fb;
    to_write = ag_biquad_process_hq(&sh->lp, to_write);
    to_write = ag_biquad_process_hq(&sh->hp, to_write);
    to_write = ag_biquad_process_hq(&sh->presence, to_write);
    to_write = ag_dcblock_process(&sh->dc, to_write);
    to_write = tanhf(to_write*0.9f)*1.05f;
    sh->buf[sh->write_pos]=to_write;
    sh->write_pos=(sh->write_pos+1)%sh->buf_size;

    /* pitch shift read: simple linear interpolation with variable speed */
    sh->read_pos+=sh->shift;
    if(sh->read_pos>=sh->buf_size) sh->read_pos-=sh->buf_size;
    int rp=(int)sh->read_pos;
    float frac=sh->read_pos - rp;
    int rp2=(rp+1)%sh->buf_size;
    float pitch_shifted = sh->buf[rp]*(1.0f-frac) + sh->buf[rp2]*frac;

    /* reverb on pitch shifted */
    float rev_l, rev_r;
    ag_reverb_process_stereo(&sh->reverb, pitch_shifted*0.5f, pitch_shifted*0.5f, &rev_l, &rev_r);
    float shimmer = (rev_l+rev_r)*0.5f*0.6f + pitch_shifted*0.4f;

    float dry_l = in_l;
    float dry_r = in_r;
    float wet_l = shimmer*0.6f + delayed*0.4f;
    float wet_r = shimmer*0.6f + delayed*0.4f;
    /* slight stereo from lfo */
    wet_l *= (1.0f + lfo*0.15f);
    wet_r *= (1.0f - lfo*0.15f);

    *out_l = (dry_l*(1.0f-sh->shimmer_mix) + wet_l*sh->shimmer_mix) * sh->gain;
    *out_r = (dry_r*(1.0f-sh->shimmer_mix) + wet_r*sh->shimmer_mix) * sh->gain;
}

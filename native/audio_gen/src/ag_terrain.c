#include "ag_terrain.h"
#include <string.h>
#include <math.h>

static void terrain_spawn_grain(AgTerrain *t);

void ag_terrain_init(AgTerrain *t, double sr, AgTerrainType type) {
    memset(t,0,sizeof(*t));
    t->sr=sr>0?sr:AG_SR_DEFAULT;
    t->gain=0.55f;
    t->density=0.32f;
    t->wetness=0.2f;
    t->type=type;
    ag_noise_init(&t->noise, 0x71A11 ^ (uint64_t)type);
    ag_noise_init(&t->noise2, 0x71A12 ^ (uint64_t)type);
    ag_rng_seed(&t->rng, 0x71A11 ^ (uint64_t)type);
    ag_biquad_init(&t->lp); ag_biquad_set(&t->lp, AG_FILTER_LP, 3800,0.72f,0,(float)sr);
    ag_biquad_init(&t->hp); ag_biquad_set(&t->hp, AG_FILTER_HP, 120,0.7f,0,(float)sr);
    ag_biquad_init(&t->bp_mid); ag_biquad_set(&t->bp_mid, AG_FILTER_BP, 1400,0.9f,0,(float)sr);
    ag_biquad_init(&t->presence); ag_biquad_set(&t->presence, AG_FILTER_HISHELF, 3000,0.7f,1.5f,(float)sr);
    ag_biquad_init(&t->low_body); ag_biquad_set(&t->low_body, AG_FILTER_LP, 280,0.72f,0,(float)sr);
    for(int i=0;i<AG_TERRAIN_GRAINS;i++){
        t->grains[i].active=0;
        ag_biquad_init(&t->grains[i].bp);
        ag_biquad_init(&t->grains[i].hp);
    }
    t->grain_interval=0.025;
    AgADSR adsr={0.001f,0.14f,0.0f,0.12f,0.7f,1.2f,1.0f,0,0};
    ag_env_init(&t->foot_env, adsr, sr);
    AgADSR adsr2={0.002f,0.22f,0.0f,0.18f,0.5f,1.2f,1.0f,0,0};
    ag_env_init(&t->foot_env2, adsr2, sr);
    ag_biquad_init(&t->foot_lp); ag_biquad_set(&t->foot_lp, AG_FILTER_LP, 420,0.72f,0,(float)sr);
    ag_biquad_init(&t->foot_bp); ag_biquad_set(&t->foot_bp, AG_FILTER_BP, 1100,1.1f,0,(float)sr);
    ag_biquad_init(&t->foot_hp); ag_biquad_set(&t->foot_hp, AG_FILTER_HP, 80,0.7f,0,(float)sr);
    ag_osc_init(&t->foot_osc, AG_OSC_SINE, sr);
    ag_dcblock_init(&t->dc);
    ag_osc_init(&t->rustle_lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&t->rustle_lfo, 0.7f);
    ag_osc_init(&t->rustle_lfo2, AG_OSC_SINE, sr); ag_osc_set_freq(&t->rustle_lfo2, 1.3f); t->rustle_lfo2.phase=0.4f;
    ag_terrain_set(t, type, t->density, t->wetness, t->gain);
}

void ag_terrain_set(AgTerrain *t, AgTerrainType type, float density, float wetness, float gain) {
    t->type=type;
    t->density=ag_clamp_f(density,0,1);
    t->wetness=ag_clamp_f(wetness,0,1);
    t->gain=ag_clamp_f(gain,0,2);
    float lp_fc, hp_fc, bp_fc, pres_gain;
    switch(type){
        case AG_TERRAIN_GRASS:
            lp_fc=3200 + wetness*800;
            hp_fc=180 + (1-wetness)*120;
            bp_fc=2200;
            pres_gain=2.0f;
            ag_biquad_set(&t->low_body, AG_FILTER_LP, 220,0.72f,0,(float)t->sr);
            ag_biquad_set(&t->foot_lp, AG_FILTER_LP, 380,0.72f,0,(float)t->sr);
            ag_biquad_set(&t->foot_bp, AG_FILTER_BP, 1800,1.0f,0,(float)t->sr);
            break;
        case AG_TERRAIN_SNOW:
            lp_fc=2800;
            hp_fc=80;
            bp_fc=900;
            pres_gain=0.5f;
            ag_biquad_set(&t->low_body, AG_FILTER_LP, 180,0.75f,0,(float)t->sr);
            ag_biquad_set(&t->foot_lp, AG_FILTER_LP, 280,0.72f,0,(float)t->sr);
            ag_biquad_set(&t->foot_bp, AG_FILTER_BP, 700,1.2f,0,(float)t->sr);
            break;
        case AG_TERRAIN_DIRT:
            lp_fc=2600;
            hp_fc=90;
            bp_fc=1100;
            pres_gain=1.0f;
            ag_biquad_set(&t->low_body, AG_FILTER_LP, 200,0.72f,0,(float)t->sr);
            break;
        case AG_TERRAIN_GRAVEL:
            lp_fc=5200;
            hp_fc=200;
            bp_fc=2800;
            pres_gain=3.0f;
            ag_biquad_set(&t->low_body, AG_FILTER_LP, 320,0.72f,0,(float)t->sr);
            break;
        case AG_TERRAIN_LEAVES:
            lp_fc=4200;
            hp_fc=250;
            bp_fc=3200;
            pres_gain=3.5f;
            ag_biquad_set(&t->low_body, AG_FILTER_LP, 260,0.72f,0,(float)t->sr);
            break;
        case AG_TERRAIN_MUD:
            lp_fc=1400;
            hp_fc=60;
            bp_fc=600;
            pres_gain=-1.0f;
            ag_biquad_set(&t->low_body, AG_FILTER_LP, 160,0.8f,0,(float)t->sr);
            ag_biquad_set(&t->foot_lp, AG_FILTER_LP, 220,0.72f,0,(float)t->sr);
            break;
        default:
            lp_fc=3500; hp_fc=120; bp_fc=1500; pres_gain=1.5f; break;
    }
    ag_biquad_set(&t->lp, AG_FILTER_LP, lp_fc,0.72f,0,(float)t->sr);
    ag_biquad_set(&t->hp, AG_FILTER_HP, hp_fc,0.7f,0,(float)t->sr);
    ag_biquad_set(&t->bp_mid, AG_FILTER_BP, bp_fc,0.9f,0,(float)t->sr);
    ag_biquad_set(&t->presence, AG_FILTER_HISHELF, 3000,0.7f,pres_gain,(float)t->sr);
}

static void terrain_spawn_grain(AgTerrain *t) {
    for(int i=0;i<AG_TERRAIN_GRAINS;i++){
        if(!t->grains[i].active){
            AgTerrainGrain *g=&t->grains[i];
            float dur_min, dur_max, freq_min, freq_max, q_min, q_max;
            switch(t->type){
                case AG_TERRAIN_GRASS: dur_min=0.008f; dur_max=0.028f; freq_min=1200; freq_max=5200; q_min=0.8f; q_max=2.0f; break;
                case AG_TERRAIN_SNOW: dur_min=0.012f; dur_max=0.045f; freq_min=600; freq_max=2200; q_min=0.7f; q_max=1.6f; break;
                case AG_TERRAIN_DIRT: dur_min=0.006f; dur_max=0.022f; freq_min=800; freq_max=3200; q_min=0.8f; q_max=1.8f; break;
                case AG_TERRAIN_GRAVEL: dur_min=0.004f; dur_max=0.018f; freq_min=1800; freq_max=6800; q_min=1.0f; q_max=2.5f; break;
                case AG_TERRAIN_LEAVES: dur_min=0.01f; dur_max=0.035f; freq_min=2000; freq_max=7200; q_min=0.9f; q_max=2.2f; break;
                case AG_TERRAIN_MUD: dur_min=0.015f; dur_max=0.05f; freq_min=400; freq_max=1600; q_min=0.6f; q_max=1.4f; break;
                default: dur_min=0.008f; dur_max=0.028f; freq_min=1000; freq_max=4000; q_min=0.8f; q_max=2.0f; break;
            }
            int len=(int)(t->sr * ag_rng_range_f32(&t->rng, dur_min, dur_max));
            if(len<32) len=32;
            if(len>AG_TERRAIN_GRAIN_LEN) len=AG_TERRAIN_GRAIN_LEN;
            g->len=len; g->pos=0;
            float freq=ag_rng_range_f32(&t->rng, freq_min, freq_max) * (0.8f + t->wetness*0.4f);
            float q=ag_rng_range_f32(&t->rng, q_min, q_max);
            float hp_fc=ag_rng_range_f32(&t->rng, 80, 400);
            ag_biquad_set(&g->bp, AG_FILTER_BP, freq, q,0,(float)t->sr);
            ag_biquad_set(&g->hp, AG_FILTER_HP, hp_fc,0.7f,0,(float)t->sr);
            for(int j=0;j<len;j++){
                float ph=(float)j/len;
                float win=0.5f-0.5f*cosf(ph*AG_TAU);
                /* shape by type */
                float n;
                if(t->type==AG_TERRAIN_SNOW){
                    n=ag_noise_pink(&t->noise)*0.6f + ag_noise_brown(&t->noise2)*0.5f + ag_noise_white(&t->noise)*0.1f;
                } else if(t->type==AG_TERRAIN_GRASS){
                    n=ag_noise_white(&t->noise)*0.5f + ag_noise_pink(&t->noise)*0.4f + ag_noise_brown(&t->noise2)*0.1f;
                } else if(t->type==AG_TERRAIN_GRAVEL){
                    n=ag_noise_white(&t->noise)*0.7f + ag_noise_pink(&t->noise)*0.2f + ag_noise_brown(&t->noise2)*0.1f;
                } else if(t->type==AG_TERRAIN_LEAVES){
                    n=ag_noise_white(&t->noise)*0.55f + ag_noise_pink(&t->noise2)*0.45f;
                } else if(t->type==AG_TERRAIN_MUD){
                    n=ag_noise_brown(&t->noise)*0.6f + ag_noise_pink(&t->noise)*0.35f + ag_noise_white(&t->noise2)*0.05f;
                } else {
                    n=ag_noise_pink(&t->noise)*0.5f + ag_noise_white(&t->noise)*0.3f + ag_noise_brown(&t->noise2)*0.2f;
                }
                n=ag_biquad_process(&g->bp, n);
                n=ag_biquad_process(&g->hp, n);
                g->buf[j]=n*win;
            }
            g->gain=ag_rng_range_f32(&t->rng,0.15f,0.75f);
            float pan=ag_rng_range_f32(&t->rng,-1,1);
            ag_buffer_pan_stereo(1.0f, pan, &g->pan_l, &g->pan_r);
            g->active=1;
            return;
        }
    }
}

float ag_terrain_next(AgTerrain *t){ float l,r; ag_terrain_next_stereo(t,&l,&r); return (l+r)*0.5f; }
void ag_terrain_next_stereo(AgTerrain *t, float *out_l, float *out_r) {
    t->timer+=1.0/t->sr;
    if(t->timer>=t->grain_interval){
        t->timer=0;
        t->grain_interval=ag_rng_range_f32(&t->rng,0.012f,0.05f) / (t->density*0.8f+0.2f);
        if(ag_rng_next_f32(&t->rng) < t->density) terrain_spawn_grain(t);
        if(t->density>0.55f && ag_rng_next_f32(&t->rng) < (t->density-0.55f)*0.7f) terrain_spawn_grain(t);
    }
    float ml=0,mr=0;
    for(int i=0;i<AG_TERRAIN_GRAINS;i++){
        AgTerrainGrain *g=&t->grains[i];
        if(!g->active) continue;
        float sm=g->buf[g->pos];
        ml+=sm*g->pan_l*g->gain;
        mr+=sm*g->pan_r*g->gain;
        g->pos++;
        if(g->pos>=g->len) g->active=0;
    }
    /* rustle LFO */
    float rust1=ag_osc_next(&t->rustle_lfo)*0.18f;
    float rust2=ag_osc_next(&t->rustle_lfo2)*0.12f;
    float bed=ag_noise_white(&t->noise)*0.03f + ag_noise_pink(&t->noise2)*0.05f;
    if(t->type==AG_TERRAIN_SNOW) bed=ag_noise_pink(&t->noise)*0.04f + ag_noise_brown(&t->noise2)*0.06f;
    else if(t->type==AG_TERRAIN_GRASS) bed=ag_noise_white(&t->noise)*0.04f + ag_noise_pink(&t->noise)*0.04f;
    bed=ag_biquad_process_hq(&t->hp, bed);
    bed=ag_biquad_process_hq(&t->lp, bed);
    bed=ag_biquad_process_hq(&t->bp_mid, bed*0.5f)*0.5f + bed*0.75f;
    bed=ag_biquad_process_hq(&t->presence, bed);
    bed*= (t->density*0.3f + 0.05f) * (1.0f + rust1 + rust2);
    ml+=bed*0.55f; mr+=bed*0.45f;

    /* footstep */
    if(t->foot_active){
        float env=ag_env_next_hq(&t->foot_env);
        float env2=ag_env_next_hq(&t->foot_env2);
        if(ag_env_is_idle(&t->foot_env) && ag_env_is_idle(&t->foot_env2)) t->foot_active=0;
        else {
            float low=0, mid=0, crunch=0;
            if(t->type==AG_TERRAIN_SNOW){
                float n=ag_noise_brown(&t->noise)*0.6f + ag_noise_pink(&t->noise)*0.4f;
                low=ag_biquad_process_hq(&t->foot_lp, n) * env * 0.7f;
                float n2=ag_noise_white(&t->noise2)*0.5f + ag_noise_pink(&t->noise2)*0.5f;
                n2=ag_biquad_process_hq(&t->foot_bp, n2);
                n2=ag_biquad_process_hq(&t->foot_hp, n2);
                crunch=n2 * env2 * 0.6f;
                mid=crunch*0.5f;
            } else if(t->type==AG_TERRAIN_GRASS){
                float n=ag_noise_pink(&t->noise)*0.5f + ag_noise_white(&t->noise)*0.3f + ag_noise_brown(&t->noise2)*0.2f;
                low=ag_biquad_process_hq(&t->low_body, n) * env * 0.4f;
                float n2=ag_noise_white(&t->noise)*0.6f;
                n2=ag_biquad_process_hq(&t->foot_bp, n2);
                mid=n2 * env2 * 0.5f;
            } else if(t->type==AG_TERRAIN_GRAVEL){
                float n=ag_noise_white(&t->noise)*0.7f;
                n=ag_biquad_process_hq(&t->foot_bp, n);
                mid=n*env2*0.7f;
                low=ag_noise_brown(&t->noise)*0.3f*env;
            } else {
                float n=ag_noise_pink(&t->noise)*0.5f + ag_noise_brown(&t->noise2)*0.4f;
                low=ag_biquad_process_hq(&t->foot_lp, n)*env*0.5f;
                float n2=ag_noise_white(&t->noise)*0.5f;
                n2=ag_biquad_process_hq(&t->foot_bp, n2);
                mid=n2*env2*0.4f;
            }
            float step = (low*0.6f + mid*0.8f + crunch*0.9f) * t->foot_gain;
            ml+=step*0.55f; mr+=step*0.45f;
        }
    }

    ml=ag_dcblock_process(&t->dc, ml);
    mr=ag_dcblock_process(&t->dc, mr);
    ml=tanhf(ml*0.88f)*1.08f;
    mr=tanhf(mr*0.88f)*1.08f;
    *out_l=ml*t->gain;
    *out_r=mr*t->gain;
}
void ag_terrain_footstep_trigger(AgTerrain *t, float vel) {
    t->foot_gain=ag_clamp_f(vel,0,1)*0.9f+0.1f;
    ag_env_trigger_vel(&t->foot_env, vel);
    ag_env_trigger_vel(&t->foot_env2, vel*0.8f);
    float freq=ag_rng_range_f32(&t->rng, 80, 180);
    ag_osc_set_freq(&t->foot_osc, freq);
    t->foot_active=1;
}
void ag_terrain_rustle_trigger(AgTerrain *t, float intensity) {
    int count=(int)(intensity*6)+1;
    for(int i=0;i<count;i++) terrain_spawn_grain(t);
}

/* Wrappers */
void ag_grass_init(AgGrass *g, double sr){ ag_terrain_init(g,sr,AG_TERRAIN_GRASS); }
float ag_grass_next(AgGrass *g){ return ag_terrain_next(g); }
void ag_grass_next_stereo(AgGrass *g, float *l,float *r){ ag_terrain_next_stereo(g,l,r); }
void ag_grass_footstep(AgGrass *g, float vel){ ag_terrain_footstep_trigger(g,vel); }

void ag_snow_init(AgSnow *s, double sr){ ag_terrain_init(s,sr,AG_TERRAIN_SNOW); s->gain=0.62f; }
float ag_snow_next(AgSnow *s){ return ag_terrain_next(s); }
void ag_snow_next_stereo(AgSnow *s, float *l,float *r){ ag_terrain_next_stereo(s,l,r); }
void ag_snow_footstep(AgSnow *s, float vel){ ag_terrain_footstep_trigger(s,vel); }
void ag_snow_crunch(AgSnow *s, float intensity){ ag_terrain_rustle_trigger(s,intensity); }

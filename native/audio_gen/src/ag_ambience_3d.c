#include "ag_ambience_3d.h"
#include <string.h>
#include <math.h>

void ag_ambience_3d_init(AgAmbience3D *amb, double sr, AgVec3 listener_pos) {
    memset(amb,0,sizeof(*amb));
    amb->sr=sr>0?sr:AG_SR_DEFAULT;
    amb->master_gain=1.0f;
    amb->master_target=1.0f;
    ag_listener_init(&amb->listener, listener_pos);
    ag_reverb_init(&amb->reverb, (int)sr);
    ag_reverb_set_room_size(&amb->reverb, 0.52f);
    ag_reverb_set_damping(&amb->reverb, 0.48f);
    ag_reverb_set_wet(&amb->reverb, 0.28f);
    ag_reverb_set_dry(&amb->reverb, 0.82f);
    ag_weather_mixer_init(&amb->weather, sr);
    ag_biome_params_default(&amb->biome_params, AG_BIOME_FOREST);
    amb->time_of_day=0.5f;
    ag_rng_seed(&amb->rng, 0xA0B);
    for(int i=0;i<AG_AMB_3D_MAX_POINT_SOURCES;i++) ag_spatializer_init(&amb->point_spats[i], (int)sr);
    /* init procedural point source generators */
    for(int i=0;i<AG_AMB_3D_MAX_POINT_SOURCES;i++){
        ag_bird_init(&amb->point_birds[i], sr, i%5);
        ag_cricket_init(&amb->point_crickets[i], sr);
        ag_fire_init(&amb->point_fires[i], sr);
    }
}
void ag_ambience_3d_set_listener(AgAmbience3D *amb, AgVec3 pos, AgVec3 forward, AgVec3 up, AgVec3 vel) {
    ag_listener_update(&amb->listener, pos, vel);
    ag_listener_set_orientation(&amb->listener, forward, up);
}
void ag_ambience_3d_set_biome(AgAmbience3D *amb, AgBiomeType biome_type, float time_of_day, float weather_intensity) {
    ag_biome_params_default(&amb->biome_params, biome_type);
    amb->biome_params.time_of_day=ag_clamp_f(time_of_day,0,1);
    amb->biome_params.weather=ag_clamp_f(weather_intensity,0,1);
    amb->time_of_day=time_of_day;
    amb->weather_intensity=weather_intensity;
    for(int i=0;i<AG_AMB_3D_MAX_LAYERS;i++){
        if(amb->layers[i].has_biome){
            ag_biome_set_params(&amb->layers[i].biome, &amb->biome_params);
        }
    }
}
void ag_ambience_3d_set_weather(AgAmbience3D *amb, AgWeatherType weather_type, float intensity) {
    amb->biome_params.weather_type=weather_type;
    amb->biome_params.weather=ag_clamp_f(intensity,0,1);
    ag_weather_mixer_set(&amb->weather, weather_type, intensity);
    for(int i=0;i<AG_AMB_3D_MAX_LAYERS;i++){
        if(amb->layers[i].has_biome){
            amb->layers[i].biome.params.weather_type=weather_type;
            amb->layers[i].biome.params.weather=intensity;
            ag_weather_mixer_set(&amb->layers[i].biome.weather, weather_type, intensity);
        }
    }
}
int ag_ambience_3d_add_point_source(AgAmbience3D *amb, AgVec3 pos, float min_dist, float max_dist, float gain) {
    if(amb->point_count >= AG_AMB_3D_MAX_POINT_SOURCES) return -1;
    int idx=amb->point_count++;
    ag_source_init(&amb->point_sources[idx], pos);
    ag_source_set_dist(&amb->point_sources[idx], min_dist, max_dist, 1.0f, AG_DIST_INVERSE);
    amb->point_gains[idx]=gain;
    amb->point_active[idx]=1;
    amb->point_gen_type[idx]= (int)(ag_rng_next_u64(&amb->rng) % 3); /* 0=bird,1=cricket,2=fire */
    return idx;
}
void ag_ambience_3d_set_point_pos(AgAmbience3D *amb, int idx, AgVec3 pos) {
    if(idx<0||idx>=amb->point_count) return;
    amb->point_sources[idx].pos=pos;
}
void ag_ambience_3d_set_point_gain(AgAmbience3D *amb, int idx, float gain) {
    if(idx<0||idx>=amb->point_count) return;
    amb->point_gains[idx]=gain;
}
void ag_ambience_3d_remove_point_source(AgAmbience3D *amb, int idx) {
    if(idx<0||idx>=amb->point_count) return;
    for(int i=idx;i<amb->point_count-1;i++){
        amb->point_sources[i]=amb->point_sources[i+1];
        amb->point_spats[i]=amb->point_spats[i+1];
        amb->point_gains[i]=amb->point_gains[i+1];
        amb->point_active[i]=amb->point_active[i+1];
        amb->point_gen_type[i]=amb->point_gen_type[i+1];
        amb->point_birds[i]=amb->point_birds[i+1];
        amb->point_crickets[i]=amb->point_crickets[i+1];
        amb->point_fires[i]=amb->point_fires[i+1];
    }
    amb->point_count--;
}
void ag_ambience_3d_add_reverb_zone(AgAmbience3D *amb, AgVec3 pos, float radius, float reverb_gain, float damping, float room_size) {
    if(amb->reverb_zone_count>=4) return;
    AgReverbZone *z=&amb->reverb_zones[amb->reverb_zone_count++];
    z->pos=pos; z->radius=radius; z->reverb_gain=reverb_gain; z->damping=damping; z->room_size=room_size;
    z->early_gain=0.25f;
    z->early_delay_ms=25.0f;
}
void ag_ambience_3d_set_master_gain(AgAmbience3D *amb, float gain, float fade_sec) {
    amb->master_target=ag_clamp_f(gain,0,1.5f);
    float dist=fabsf(amb->master_target-amb->master_gain);
    if(fade_sec<=0.0001f) amb->master_step=dist>0?dist:1.0f;
    else amb->master_step=dist/(fade_sec*(float)amb->sr);
    if(amb->master_step<1e-12f) amb->master_step=1e-12f;
}
static void ramp_toward(float *v, float tgt, float step){
    if(*v<tgt){ *v+=step; if(*v>tgt) *v=tgt; }
    else if(*v>tgt){ *v-=step; if(*v<tgt) *v=tgt; }
}

float ag_ambience_3d_next(AgAmbience3D *amb, float *out_l, float *out_r) {
    float buf[2]; ag_ambience_3d_render(amb, buf, 1);
    *out_l=buf[0]; *out_r=buf[1];
    return (buf[0]+buf[1])*0.5f;
}
void ag_ambience_3d_render(AgAmbience3D *amb, float *stereo_interleaved, int frames) {
    for(int f=0; f<frames; f++){
        amb->time+=1.0/amb->sr;
        float mix_l=0, mix_r=0;

        /* Layers (biome beds) HQ */
        for(int i=0;i<AG_AMB_3D_MAX_LAYERS;i++){
            AgAmbLayer *layer=&amb->layers[i];
            if(!layer->active) continue;
            ramp_toward(&layer->gain, layer->gain_target, layer->gain_step);
            float l=0,r=0;
            if(layer->has_biome){
                ag_biome_next_stereo(&layer->biome, &l, &r);
            } else {
                continue;
            }
            /* layer filtering based on zone distance */
            if(layer->zone_radius>0.1f){
                float d = ag_vec3_dist(layer->zone_pos, amb->listener.pos);
                float zone_gain = 1.0f - d/layer->zone_radius;
                if(zone_gain<0) zone_gain=0;
                zone_gain = zone_gain*zone_gain*(3.0f-2.0f*zone_gain);
                l*=zone_gain; r*=zone_gain;
            }
            mix_l+=l*layer->gain;
            mix_r+=r*layer->gain;
        }

        /* Point sources HQ - procedural per type */
        for(int s=0;s<amb->point_count;s++){
            if(!amb->point_active[s]) continue;
            float src_l=0, src_r=0;
            switch(amb->point_gen_type[s]){
                case 0: /* bird */
                    ag_bird_auto(&amb->point_birds[s], 0.5f);
                    ag_bird_next_stereo(&amb->point_birds[s], &src_l, &src_r);
                    break;
                case 1: /* cricket */
                    ag_cricket_next_stereo(&amb->point_crickets[s], &src_l, &src_r);
                    break;
                case 2: /* fire */
                    ag_fire_next_stereo(&amb->point_fires[s], &src_l, &src_r);
                    break;
                default: {
                    float t = (float)amb->time;
                    float mono = sinf(t * (200.0f + s*53.0f) * 0.11f) * 0.09f + (ag_rng_next_f32(&amb->rng)*0.02f-0.01f);
                    src_l=mono*0.5f; src_r=mono*0.5f;
                } break;
            }
            float mono_for_spat = (src_l+src_r)*0.5f;
            float l,r;
            ag_spatializer_process_high_quality(&amb->point_spats[s], &amb->point_sources[s], &amb->listener, mono_for_spat, &l, &r);
            /* preserve some stereo from source */
            l = l*0.7f + src_l*0.3f;
            r = r*0.7f + src_r*0.3f;
            mix_l+=l*amb->point_gains[s];
            mix_r+=r*amb->point_gains[s];
        }

        /* Weather HQ */
        float wl,wr; ag_weather_mixer_next_stereo(&amb->weather, &wl, &wr);
        mix_l+=wl*0.9f;
        mix_r+=wr*0.9f;

        /* Reverb zones HQ */
        float reverb_gain=0;
        float early_gain=0;
        for(int i=0;i<amb->reverb_zone_count;i++){
            float rg = ag_3d_reverb_zone_gain(&amb->reverb_zones[i], amb->listener.pos);
            reverb_gain+=rg;
            early_gain+=rg*amb->reverb_zones[i].early_gain;
        }
        reverb_gain=ag_clamp_f(reverb_gain,0,1);
        if(reverb_gain>0.01f){
            /* dynamic reverb params based on zone */
            float avg_damp=0.5f, avg_room=0.6f;
            if(amb->reverb_zone_count>0){
                float sum_d=0,sum_r=0;
                for(int i=0;i<amb->reverb_zone_count;i++){ sum_d+=amb->reverb_zones[i].damping; sum_r+=amb->reverb_zones[i].room_size; }
                avg_damp=sum_d/amb->reverb_zone_count;
                avg_room=sum_r/amb->reverb_zone_count;
            }
            ag_reverb_set_damping(&amb->reverb, avg_damp);
            ag_reverb_set_room_size(&amb->reverb, avg_room);
            ag_reverb_set_wet(&amb->reverb, reverb_gain*0.42f);
            ag_reverb_set_dry(&amb->reverb, 1.0f - reverb_gain*0.22f);
            float rev_l, rev_r;
            ag_reverb_process_stereo(&amb->reverb, mix_l, mix_r, &rev_l, &rev_r);
            /* blend dry/wet with early reflections */
            mix_l = rev_l*(0.7f+early_gain*0.2f) + mix_l*0.3f;
            mix_r = rev_r*(0.7f+early_gain*0.2f) + mix_r*0.3f;
        }

        ramp_toward(&amb->master_gain, amb->master_target, amb->master_step);
        mix_l*=amb->master_gain;
        mix_r*=amb->master_gain;

        /* HQ soft clip with tanh + limiter */
        mix_l = tanhf(mix_l*0.88f)*1.12f;
        mix_r = tanhf(mix_r*0.88f)*1.12f;
        mix_l = ag_clamp_f(mix_l, -1.25f, 1.25f);
        mix_r = ag_clamp_f(mix_r, -1.25f, 1.25f);

        stereo_interleaved[f*2]=mix_l;
        stereo_interleaved[f*2+1]=mix_r;
    }
}

void ag_ambience_3d_preset_forest(AgAmbience3D *amb) {
    ag_ambience_3d_set_biome(amb, AG_BIOME_FOREST, 0.52f, 0.0f);
    for(int i=0;i<AG_AMB_3D_MAX_LAYERS;i++) if(!amb->layers[i].active){
        amb->layers[i].active=1;
        amb->layers[i].gain=0.62f; amb->layers[i].gain_target=0.62f; amb->layers[i].gain_step=0.0001f;
        amb->layers[i].has_biome=1;
        AgBiomeParams p; ag_biome_params_default(&p, AG_BIOME_FOREST);
        p.seed=ag_rng_next_u64(&amb->rng);
        p.time_of_day=0.52f;
        ag_biome_init(&amb->layers[i].biome, &p, amb->sr);
        break;
    }
    /* add some point sources: birds */
    ag_ambience_3d_add_point_source(amb, ag_vec3(5,2, -3), 1.0f, 25.0f, 0.6f);
    ag_ambience_3d_add_point_source(amb, ag_vec3(-4,3, 2), 1.0f, 25.0f, 0.5f);
}
void ag_ambience_3d_preset_cave(AgAmbience3D *amb) {
    ag_ambience_3d_set_biome(amb, AG_BIOME_CAVE, 0.0f, 0.0f);
    for(int i=0;i<AG_AMB_3D_MAX_LAYERS;i++) if(!amb->layers[i].active){
        amb->layers[i].active=1;
        amb->layers[i].gain=0.52f; amb->layers[i].gain_target=0.52f; amb->layers[i].gain_step=0.0001f;
        amb->layers[i].has_biome=1;
        AgBiomeParams p; ag_biome_params_default(&p, AG_BIOME_CAVE);
        p.seed=ag_rng_next_u64(&amb->rng);
        ag_biome_init(&amb->layers[i].biome, &p, amb->sr);
        break;
    }
    ag_ambience_3d_add_reverb_zone(amb, ag_vec3(0,0,0), 22.0f, 0.82f, 0.62f, 0.92f);
}
void ag_ambience_3d_preset_ocean(AgAmbience3D *amb) {
    ag_ambience_3d_set_biome(amb, AG_BIOME_OCEAN, 0.5f, 0.12f);
    for(int i=0;i<AG_AMB_3D_MAX_LAYERS;i++) if(!amb->layers[i].active){
        amb->layers[i].active=1;
        amb->layers[i].gain=0.72f; amb->layers[i].gain_target=0.72f; amb->layers[i].gain_step=0.0001f;
        amb->layers[i].has_biome=1;
        AgBiomeParams p; ag_biome_params_default(&p, AG_BIOME_OCEAN);
        p.seed=ag_rng_next_u64(&amb->rng);
        ag_biome_init(&amb->layers[i].biome, &p, amb->sr);
        break;
    }
    ag_ambience_3d_add_point_source(amb, ag_vec3(10,0, -5), 2.0f, 40.0f, 0.4f);
}
void ag_ambience_3d_preset_city(AgAmbience3D *amb) {
    ag_ambience_3d_set_biome(amb, AG_BIOME_CITY, 0.5f, 0.0f);
    for(int i=0;i<AG_AMB_3D_MAX_LAYERS;i++) if(!amb->layers[i].active){
        amb->layers[i].active=1;
        amb->layers[i].gain=0.42f; amb->layers[i].gain_target=0.42f; amb->layers[i].gain_step=0.0001f;
        amb->layers[i].has_biome=1;
        AgBiomeParams p; ag_biome_params_default(&p, AG_BIOME_CITY);
        p.seed=ag_rng_next_u64(&amb->rng);
        ag_biome_init(&amb->layers[i].biome, &p, amb->sr);
        break;
    }
}
void ag_ambience_3d_preset_nexus(AgAmbience3D *amb) {
    ag_ambience_3d_set_biome(amb, AG_BIOME_NEXUS, 0.5f, 0.0f);
    for(int i=0;i<AG_AMB_3D_MAX_LAYERS;i++) if(!amb->layers[i].active){
        amb->layers[i].active=1;
        amb->layers[i].gain=0.62f; amb->layers[i].gain_target=0.62f; amb->layers[i].gain_step=0.0001f;
        amb->layers[i].has_biome=1;
        AgBiomeParams p; ag_biome_params_default(&p, AG_BIOME_NEXUS);
        p.seed=ag_rng_next_u64(&amb->rng);
        ag_biome_init(&amb->layers[i].biome, &p, amb->sr);
        break;
    }
    ag_ambience_3d_add_reverb_zone(amb, ag_vec3(0,0,0), 32.0f, 0.62f, 0.42f, 0.72f);
}
void ag_ambience_3d_preset_for_scene(AgAmbience3D *amb, const char *scene_name) {
    AgBiomeType bt = ag_biome_from_string(scene_name);
    ag_ambience_3d_set_biome(amb, bt, 0.5f, 0.0f);
    for(int i=0;i<AG_AMB_3D_MAX_LAYERS;i++) if(!amb->layers[i].active){
        amb->layers[i].active=1;
        amb->layers[i].gain=0.62f; amb->layers[i].gain_target=0.62f; amb->layers[i].gain_step=0.0001f;
        amb->layers[i].has_biome=1;
        AgBiomeParams p; ag_biome_params_default(&p, bt);
        p.seed=ag_rng_next_u64(&amb->rng);
        ag_biome_init(&amb->layers[i].biome, &p, amb->sr);
        break;
    }
    if(bt==AG_BIOME_CAVE || bt==AG_BIOME_NEXUS){
        ag_ambience_3d_add_reverb_zone(amb, ag_vec3(0,0,0), 26.0f, 0.72f, 0.52f, 0.82f);
    }
}

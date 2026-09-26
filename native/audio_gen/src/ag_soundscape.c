#include "ag_soundscape.h"
#include <string.h>
#include <math.h>
#include <stdlib.h>

void ag_soundscape_params_default(AgSoundscapeParams *p) {
    memset(p,0,sizeof(*p));
    p->biome=AG_BIOME_FOREST;
    p->mood=AG_MOOD_CALM;
    p->weather=AG_WEATHER_CLEAR;
    p->weather_intensity=0.0f;
    p->time_of_day=0.5f;
    p->music_gain=0.55f;
    p->ambience_gain=1.0f;
    p->master_gain=1.0f;
    p->seed=1;
    p->use_3d=1;
    p->use_music=1;
}
void ag_soundscape_params_for_scene(const char *scene_name, AgSoundscapeParams *p, uint64_t seed) {
    ag_soundscape_params_default(p);
    p->seed=seed?seed:1;
    if(!scene_name) scene_name="classroom";
    if(strcmp(scene_name,"classroom")==0){
        p->biome=AG_BIOME_CITY; p->mood=AG_MOOD_CALM; p->time_of_day=0.6f; p->music_gain=0.38f; p->ambience_gain=0.32f;
    } else if(strcmp(scene_name,"grove")==0){
        p->biome=AG_BIOME_FOREST; p->mood=AG_MOOD_DREAM; p->time_of_day=0.52f; p->music_gain=0.42f; p->ambience_gain=0.62f;
    } else if(strcmp(scene_name,"shore")==0){
        p->biome=AG_BIOME_BEACH; p->mood=AG_MOOD_WARM; p->time_of_day=0.62f; p->music_gain=0.38f; p->ambience_gain=0.72f;
    } else if(strcmp(scene_name,"nexus")==0){
        p->biome=AG_BIOME_NEXUS; p->mood=AG_MOOD_TENSE; p->time_of_day=0.5f; p->music_gain=0.48f; p->ambience_gain=0.62f; p->use_3d=1;
    } else if(strcmp(scene_name,"rift")==0){
        p->biome=AG_BIOME_RIFT; p->mood=AG_MOOD_RIFT; p->time_of_day=0.22f; p->music_gain=0.58f; p->ambience_gain=0.52f; p->use_3d=1;
    } else if(strcmp(scene_name,"core")==0){
        p->biome=AG_BIOME_CAVE; p->mood=AG_MOOD_TENSE; p->time_of_day=0.0f; p->music_gain=0.52f; p->ambience_gain=0.52f;
    } else if(strcmp(scene_name,"lab")==0){
        p->biome=AG_BIOME_LAB; p->mood=AG_MOOD_LAB; p->time_of_day=0.72f; p->music_gain=0.48f; p->ambience_gain=0.22f;
    } else if(strcmp(scene_name,"festival")==0){
        p->biome=AG_BIOME_CITY; p->mood=AG_MOOD_FESTIVAL; p->time_of_day=0.82f; p->music_gain=0.58f; p->ambience_gain=0.52f;
    } else if(strcmp(scene_name,"sanctum")==0){
        p->biome=AG_BIOME_CAVE; p->mood=AG_MOOD_AMBIENT; p->time_of_day=0.32f; p->music_gain=0.48f; p->ambience_gain=0.62f;
    } else if(strcmp(scene_name,"alley")==0){
        p->biome=AG_BIOME_CITY; p->mood=AG_MOOD_NIGHT; p->time_of_day=0.12f; p->music_gain=0.42f; p->ambience_gain=0.42f; p->weather=AG_WEATHER_RAIN_LIGHT; p->weather_intensity=0.32f;
    } else if(strcmp(scene_name,"lighthouse")==0){
        p->biome=AG_BIOME_OCEAN; p->mood=AG_MOOD_CALM; p->time_of_day=0.42f; p->music_gain=0.38f; p->ambience_gain=0.72f;
    }
}

void ag_soundscape_init(AgSoundscape *ss, const AgSoundscapeParams *params, double sr) {
    memset(ss,0,sizeof(*ss));
    ss->sr=sr>0?sr:AG_SR_DEFAULT;
    ss->params=*params;
    ss->gain=params->master_gain;
    ag_rng_seed(&ss->rng, params->seed?params->seed:1);

    ag_ambience_3d_init(&ss->ambience_3d, sr, ag_vec3(0,0,0));
    ag_ambience_3d_preset_for_scene(&ss->ambience_3d, ag_biome_to_string(params->biome));
    ag_ambience_3d_set_biome(&ss->ambience_3d, params->biome, params->time_of_day, params->weather_intensity);
    ag_ambience_3d_set_weather(&ss->ambience_3d, params->weather, params->weather_intensity);

    AgBiomeParams bp; ag_biome_params_default(&bp, params->biome);
    bp.time_of_day=params->time_of_day;
    bp.weather=params->weather_intensity;
    bp.weather_type=params->weather;
    bp.seed=params->seed;
    ag_biome_init(&ss->biome, &bp, sr);

    ag_proc_mixer_init(&ss->music_mixer, sr);
    if(params->use_music){
        AgProcSpec spec; ag_proc_spec_from_mood(&spec, params->mood, 60, 80, params->seed);
        spec.id=ag_rng_next_u64(&ss->rng);
        ag_proc_mixer_transition(&ss->music_mixer, &spec, 0.8f);
        ag_proc_mixer_set_gain(&ss->music_mixer, params->music_gain, 0.5f);
    }

    ag_weather_mixer_init(&ss->weather, sr);
    ag_weather_mixer_set(&ss->weather, params->weather, params->weather_intensity);

    /* HQ mastering: limiter state */
    ss->limiter_gain=1.0f;
    ss->limiter_env=0.0f;
}
void ag_soundscape_set_params(AgSoundscape *ss, const AgSoundscapeParams *params, float fade_sec) {
    ss->params=*params;
    ag_ambience_3d_set_biome(&ss->ambience_3d, params->biome, params->time_of_day, params->weather_intensity);
    ag_ambience_3d_set_weather(&ss->ambience_3d, params->weather, params->weather_intensity);
    AgBiomeParams bp;
    ag_biome_params_default(&bp, params->biome);
    bp.time_of_day=params->time_of_day;
    bp.weather=params->weather_intensity;
    bp.weather_type=params->weather;
    bp.seed=params->seed;
    /* preserve wind/water etc from type */
    ag_biome_set_params(&ss->biome, &bp);
    if(params->use_music){
        AgProcSpec spec; ag_proc_spec_from_mood(&spec, params->mood, 60, 80, ag_rng_next_u64(&ss->rng));
        spec.id=ag_rng_next_u64(&ss->rng);
        ag_proc_mixer_transition(&ss->music_mixer, &spec, fade_sec);
    }
    ag_weather_mixer_set(&ss->weather, params->weather, params->weather_intensity);
    ag_ambience_3d_set_master_gain(&ss->ambience_3d, params->ambience_gain, fade_sec);
    ag_proc_mixer_set_gain(&ss->music_mixer, params->music_gain, fade_sec);
}
void ag_soundscape_set_time_of_day(AgSoundscape *ss, float tod, float fade_sec) {
    ss->params.time_of_day=ag_clamp_f(tod,0,1);
    ag_ambience_3d_set_biome(&ss->ambience_3d, ss->params.biome, tod, ss->params.weather_intensity);
    AgBiomeParams bp = ss->biome.params;
    bp.time_of_day=tod;
    ag_biome_set_params(&ss->biome, &bp);
    (void)fade_sec;
}
void ag_soundscape_set_weather(AgSoundscape *ss, AgWeatherType weather, float intensity, float fade_sec) {
    ss->params.weather=weather;
    ss->params.weather_intensity=ag_clamp_f(intensity,0,1);
    ag_ambience_3d_set_weather(&ss->ambience_3d, weather, intensity);
    ag_weather_mixer_set(&ss->weather, weather, intensity);
    (void)fade_sec;
}
void ag_soundscape_set_mood(AgSoundscape *ss, AgMood mood, float fade_sec) {
    ss->params.mood=mood;
    AgProcSpec spec; ag_proc_spec_from_mood(&spec, mood, 60, 80, ag_rng_next_u64(&ss->rng));
    spec.id=ag_rng_next_u64(&ss->rng);
    ag_proc_mixer_transition(&ss->music_mixer, &spec, fade_sec);
}

void ag_soundscape_render(AgSoundscape *ss, float *stereo_interleaved, int frames) {
    float *amb_buf = (float*)malloc(sizeof(float)*frames*2);
    float *music_buf = (float*)malloc(sizeof(float)*frames*2);
    float *weather_buf = (float*)malloc(sizeof(float)*frames*2);
    if(!amb_buf || !music_buf || !weather_buf){ free(amb_buf); free(music_buf); free(weather_buf); return; }

    if(ss->params.use_3d){
        ag_ambience_3d_render(&ss->ambience_3d, amb_buf, frames);
    } else {
        ag_biome_render(&ss->biome, amb_buf, frames);
    }

    if(ss->params.use_music){
        ag_proc_mixer_render(&ss->music_mixer, music_buf, frames);
    } else {
        memset(music_buf,0,sizeof(float)*frames*2);
    }

    for(int i=0;i<frames;i++){
        float wl,wr; ag_weather_mixer_next_stereo(&ss->weather, &wl, &wr);
        weather_buf[i*2]=wl;
        weather_buf[i*2+1]=wr;
    }

    /* HQ mixing with sidechain-like ducking and EQ */
    for(int i=0;i<frames;i++){
        int idx=i*2;
        float amb_l = amb_buf[idx] * ss->params.ambience_gain;
        float amb_r = amb_buf[idx+1] * ss->params.ambience_gain;
        float mus_l = music_buf[idx] * ss->params.music_gain;
        float mus_r = music_buf[idx+1] * ss->params.music_gain;
        float wea_l = weather_buf[idx] * ss->params.weather_intensity * 0.55f;
        float wea_r = weather_buf[idx+1] * ss->params.weather_intensity * 0.55f;

        /* gentle sidechain: music ducks slightly when weather is loud */
        float weather_env = (fabsf(wea_l)+fabsf(wea_r))*0.5f;
        weather_env = ag_clamp_f(weather_env*2.0f, 0, 0.35f);
        float music_duck = 1.0f - weather_env*0.25f;
        mus_l*=music_duck; mus_r*=music_duck;

        /* ambience ducks slightly when music has strong transient (very simple) */
        float music_env = (fabsf(mus_l)+fabsf(mus_r))*0.5f;
        float amb_duck = 1.0f - ag_clamp_f(music_env*1.5f,0,0.2f);
        amb_l*=amb_duck; amb_r*=amb_duck;

        float out_l = amb_l + mus_l + wea_l;
        float out_r = amb_r + mus_r + wea_r;

        /* HQ soft clip with 2-stage */
        out_l = tanhf(out_l*0.85f)*1.15f;
        out_r = tanhf(out_r*0.85f)*1.15f;
        /* second stage for loud */
        if(fabsf(out_l)>0.9f) out_l = 0.9f*tanhf(out_l*1.1f/0.9f);
        if(fabsf(out_r)>0.9f) out_r = 0.9f*tanhf(out_r*1.1f/0.9f);

        /* simple limiter */
        float peak = fmaxf(fabsf(out_l), fabsf(out_r));
        if(peak>ss->limiter_env) ss->limiter_env = ss->limiter_env*0.92f + peak*0.08f;
        else ss->limiter_env = ss->limiter_env*0.995f + peak*0.005f;
        if(ss->limiter_env>1.0f){
            float gain = 1.0f / ss->limiter_env;
            gain = ag_clamp_f(gain, 0.6f, 1.0f);
            ss->limiter_gain = ss->limiter_gain*0.9f + gain*0.1f;
        } else {
            ss->limiter_gain = ss->limiter_gain*0.995f + 1.0f*0.005f;
        }
        out_l*=ss->limiter_gain;
        out_r*=ss->limiter_gain;

        stereo_interleaved[idx]=out_l * ss->params.master_gain;
        stereo_interleaved[idx+1]=out_r * ss->params.master_gain;
    }

    free(amb_buf); free(music_buf); free(weather_buf);
    ss->time+= (double)frames / ss->sr;
}
float ag_soundscape_next(AgSoundscape *ss, float *l, float *r) {
    float buf[2]; ag_soundscape_render(ss, buf, 1);
    *l=buf[0]; *r=buf[1];
    return (buf[0]+buf[1])*0.5f;
}

void ag_soundscape_preset_classroom(AgSoundscape *ss) {
    AgSoundscapeParams p; ag_soundscape_params_for_scene("classroom",&p,1);
    ag_soundscape_set_params(ss,&p,0.8f);
}
void ag_soundscape_preset_grove(AgSoundscape *ss) {
    AgSoundscapeParams p; ag_soundscape_params_for_scene("grove",&p,2);
    ag_soundscape_set_params(ss,&p,0.8f);
}
void ag_soundscape_preset_shore(AgSoundscape *ss) {
    AgSoundscapeParams p; ag_soundscape_params_for_scene("shore",&p,3);
    ag_soundscape_set_params(ss,&p,0.8f);
}
void ag_soundscape_preset_nexus(AgSoundscape *ss) {
    AgSoundscapeParams p; ag_soundscape_params_for_scene("nexus",&p,4);
    ag_soundscape_set_params(ss,&p,0.8f);
}
void ag_soundscape_preset_rift(AgSoundscape *ss) {
    AgSoundscapeParams p; ag_soundscape_params_for_scene("rift",&p,5);
    ag_soundscape_set_params(ss,&p,0.8f);
}
void ag_soundscape_preset_lab(AgSoundscape *ss) {
    AgSoundscapeParams p; ag_soundscape_params_for_scene("lab",&p,6);
    ag_soundscape_set_params(ss,&p,0.8f);
}
void ag_soundscape_preset_festival(AgSoundscape *ss) {
    AgSoundscapeParams p; ag_soundscape_params_for_scene("festival",&p,7);
    ag_soundscape_set_params(ss,&p,0.8f);
}

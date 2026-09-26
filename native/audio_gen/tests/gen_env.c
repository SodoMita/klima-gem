#include <stdio.h>
#include <stdlib.h>
#include "../include/audio_gen.h"

#define SR 44100

static void gen_3d(void) {
    printf("=== 3D spatialization ===\n");
    AgListener lis; ag_listener_init(&lis, ag_vec3(0,0,0));
    ag_listener_set_orientation(&lis, ag_vec3(0,0,-1), ag_vec3(0,1,0));
    AgSource src; ag_source_init(&src, ag_vec3(5,0,0));
    ag_source_set_dist(&src, 1, 20, 1, AG_DIST_INVERSE);
    AgSpatializer spat; ag_spatializer_init(&spat, SR);
    float buf[SR*2];
    for(int i=0;i<SR;i++){
        float mono = sinf(2.0f*3.14159f*440.0f*i/SR)*0.5f;
        float l,r; ag_spatializer_process(&spat, &src, &lis, mono, &l, &r);
        buf[i*2]=l; buf[i*2+1]=r;
    }
    ag_wav_write_f32("/tmp/ag_3d_pan.wav", buf, SR, 2, SR);
    printf("wrote 3d pan\n");

    /* moving source */
    Ag3DMixer mixer; ag_3d_mixer_init(&mixer, SR, ag_vec3(0,0,0));
    int idx = ag_3d_mixer_add_source(&mixer, ag_vec3(0,0,-5), 1, 30);
    float *mono_bufs = (float*)malloc(sizeof(float)*SR*1);
    for(int i=0;i<SR;i++) mono_bufs[i]= sinf(2.0f*3.14159f*220.0f*i/SR)*0.5f;
    float *stereo = (float*)malloc(sizeof(float)*SR*2);
    for(int i=0;i<SR;i++){
        float angle = (float)i/SR * 2.0f*3.14159f;
        AgVec3 pos = ag_vec3(sinf(angle)*5, 0, cosf(angle)*5 -5);
        ag_3d_mixer_set_source_pos(&mixer, idx, pos);
        float in = mono_bufs[i];
        float l,r; ag_spatializer_process(&mixer.spatializers[idx], &mixer.sources[idx], &mixer.listener, in, &l, &r);
        stereo[i*2]=l; stereo[i*2+1]=r;
    }
    ag_wav_write_f32("/tmp/ag_3d_moving.wav", stereo, SR, 2, SR);
    printf("wrote 3d moving\n");
    free(mono_bufs); free(stereo);
}

static void gen_water(void){
    printf("=== Water ===\n");
    float *buf = (float*)malloc(sizeof(float)*SR*6);
    AgOcean ocean; ag_ocean_init(&ocean, SR);
    for(int i=0;i<SR*4;i++) buf[i]=ag_ocean_next(&ocean);
    ag_wav_write_f32("/tmp/ag_env_ocean.wav", buf, SR*4, 1, SR);
    printf("wrote ocean\n");

    AgRiver river; ag_river_init(&river, SR);
    for(int i=0;i<SR*4;i++) buf[i]=ag_river_next(&river);
    ag_wav_write_f32("/tmp/ag_env_river.wav", buf, SR*4, 1, SR);
    printf("wrote river\n");

    AgWaterfall wf; ag_waterfall_init(&wf, SR);
    for(int i=0;i<SR*4;i++) buf[i]=ag_waterfall_next(&wf);
    ag_wav_write_f32("/tmp/ag_env_waterfall.wav", buf, SR*4, 1, SR);
    printf("wrote waterfall\n");

    AgDrip drip; ag_drip_init(&drip, SR);
    for(int i=0;i<SR*6;i++){ ag_drip_auto(&drip, 0.5f); buf[i]=ag_drip_next(&drip); }
    ag_wav_write_f32("/tmp/ag_env_drip.wav", buf, SR*6, 1, SR);
    printf("wrote drip\n");

    AgBubbles bub; ag_bubbles_init(&bub, SR);
    for(int i=0;i<SR*4;i++) buf[i]=ag_bubbles_next(&bub);
    ag_wav_write_f32("/tmp/ag_env_bubbles.wav", buf, SR*4, 1, SR);
    printf("wrote bubbles\n");
    free(buf);
}

static void gen_fire(void){
    printf("=== Fire ===\n");
    float *buf = (float*)malloc(sizeof(float)*SR*4);
    AgFire fire; ag_fire_init(&fire, SR);
    for(int i=0;i<SR*4;i++) buf[i]=ag_fire_next(&fire);
    ag_wav_write_f32("/tmp/ag_env_fire.wav", buf, SR*4, 1, SR);
    printf("wrote fire\n");

    AgFireplace fp; ag_fireplace_init(&fp, SR);
    for(int i=0;i<SR*4;i++) buf[i]=ag_fireplace_next(&fp);
    ag_wav_write_f32("/tmp/ag_env_fireplace.wav", buf, SR*4, 1, SR);
    printf("wrote fireplace\n");

    AgBonfire bf; ag_bonfire_init(&bf, SR);
    for(int i=0;i<SR*4;i++) buf[i]=ag_bonfire_next(&bf);
    ag_wav_write_f32("/tmp/ag_env_bonfire.wav", buf, SR*4, 1, SR);
    printf("wrote bonfire\n");
    free(buf);
}

static void gen_nature(void){
    printf("=== Nature ===\n");
    float *buf = (float*)malloc(sizeof(float)*SR*10);
    AgBird bird; ag_bird_init(&bird, SR, 0);
    for(int i=0;i<SR*6;i++){ ag_bird_auto(&bird, 0.5f); buf[i]=ag_bird_next(&bird); }
    ag_wav_write_f32("/tmp/ag_env_birds.wav", buf, SR*6, 1, SR);
    printf("wrote birds\n");

    AgCricket cricket; ag_cricket_init(&cricket, SR);
    for(int i=0;i<SR*4;i++) buf[i]=ag_cricket_next(&cricket);
    ag_wav_write_f32("/tmp/ag_env_cricket.wav", buf, SR*4, 1, SR);
    printf("wrote cricket\n");

    AgCicada cicada; ag_cicada_init(&cicada, SR);
    for(int i=0;i<SR*4;i++) buf[i]=ag_cicada_next(&cicada);
    ag_wav_write_f32("/tmp/ag_env_cicada.wav", buf, SR*4, 1, SR);
    printf("wrote cicada\n");

    AgFrog frog; ag_frog_init(&frog, SR);
    for(int i=0;i<SR*6;i++) buf[i]=ag_frog_next(&frog);
    ag_wav_write_f32("/tmp/ag_env_frog.wav", buf, SR*6, 1, SR);
    printf("wrote frog\n");

    AgOwl owl; ag_owl_init(&owl, SR);
    for(int i=0;i<SR*10;i++) buf[i]=ag_owl_next(&owl);
    ag_wav_write_f32("/tmp/ag_env_owl.wav", buf, SR*10, 1, SR);
    printf("wrote owl\n");

    AgInsectSwarm swarm; ag_swarm_init(&swarm, SR);
    swarm.density=0.6f;
    float *stereo = (float*)malloc(sizeof(float)*SR*4*2);
    for(int i=0;i<SR*4;i++){ float l,r; ag_swarm_next_stereo(&swarm,&l,&r); stereo[i*2]=l; stereo[i*2+1]=r; }
    ag_wav_write_f32("/tmp/ag_env_swarm.wav", stereo, SR*4, 2, SR);
    printf("wrote swarm\n");
    free(stereo);
    free(buf);
}

static void gen_weather(void){
    printf("=== Weather ===\n");
    float *stereo = (float*)malloc(sizeof(float)*SR*10*2);
    AgWeatherMixer wm; ag_weather_mixer_init(&wm, SR);

    ag_weather_mixer_set(&wm, AG_WEATHER_RAIN_LIGHT, 0.6f);
    for(int i=0;i<SR*6;i++){ float l,r; ag_weather_mixer_next_stereo(&wm,&l,&r); stereo[i*2]=l; stereo[i*2+1]=r; }
    ag_wav_write_f32("/tmp/ag_weather_rain_light.wav", stereo, SR*6, 2, SR);
    printf("wrote rain light\n");

    ag_weather_mixer_set(&wm, AG_WEATHER_RAIN_HEAVY, 0.8f);
    for(int i=0;i<SR*6;i++){ float l,r; ag_weather_mixer_next_stereo(&wm,&l,&r); stereo[i*2]=l; stereo[i*2+1]=r; }
    ag_wav_write_f32("/tmp/ag_weather_rain_heavy.wav", stereo, SR*6, 2, SR);
    printf("wrote rain heavy\n");

    ag_weather_mixer_set(&wm, AG_WEATHER_THUNDERSTORM, 0.9f);
    for(int i=0;i<SR*10;i++){ float l,r; ag_weather_mixer_next_stereo(&wm,&l,&r); stereo[i*2]=l; stereo[i*2+1]=r; }
    ag_wav_write_f32("/tmp/ag_weather_thunderstorm.wav", stereo, SR*10, 2, SR);
    printf("wrote thunderstorm\n");

    ag_weather_mixer_set(&wm, AG_WEATHER_WINDY, 0.7f);
    for(int i=0;i<SR*6;i++){ float l,r; ag_weather_mixer_next_stereo(&wm,&l,&r); stereo[i*2]=l; stereo[i*2+1]=r; }
    ag_wav_write_f32("/tmp/ag_weather_windy.wav", stereo, SR*6, 2, SR);
    printf("wrote windy\n");
    free(stereo);
}

static void gen_biomes(void){
    printf("=== Biomes ===\n");
    float *stereo = (float*)malloc(sizeof(float)*SR*10*2);
    AgBiomeType types[] = {AG_BIOME_FOREST, AG_BIOME_CAVE, AG_BIOME_DESERT, AG_BIOME_OCEAN, AG_BIOME_JUNGLE, AG_BIOME_SWAMP, AG_BIOME_MOUNTAIN, AG_BIOME_RIVER, AG_BIOME_BEACH, AG_BIOME_NEXUS, AG_BIOME_RIFT};
    for(size_t i=0;i<sizeof(types)/sizeof(types[0]);i++){
        AgBiomeParams bp; ag_biome_params_default(&bp, types[i]);
        bp.seed=100+i;
        bp.time_of_day=0.5f;
        AgBiome biome; ag_biome_init(&biome, &bp, SR);
        ag_biome_render(&biome, stereo, SR*10);
        char path[256]; snprintf(path,sizeof(path),"/tmp/ag_biome_%s.wav", ag_biome_to_string(types[i]));
        ag_wav_write_f32(path, stereo, SR*10, 2, SR);
        printf("wrote %s\n", path);
    }
    free(stereo);
}

static void gen_ambience_3d(void){
    printf("=== 3D Ambience ===\n");
    float *stereo = (float*)malloc(sizeof(float)*SR*10*2);
    AgAmbience3D amb; ag_ambience_3d_init(&amb, SR, ag_vec3(0,0,0));
    ag_ambience_3d_preset_forest(&amb);
    ag_ambience_3d_render(&amb, stereo, SR*10);
    ag_wav_write_f32("/tmp/ag_amb3d_forest.wav", stereo, SR*10, 2, SR);
    printf("wrote 3d forest\n");
    ag_reverb_free(&amb.reverb);

    ag_ambience_3d_init(&amb, SR, ag_vec3(0,0,0));
    ag_ambience_3d_preset_cave(&amb);
    ag_ambience_3d_render(&amb, stereo, SR*10);
    ag_wav_write_f32("/tmp/ag_amb3d_cave.wav", stereo, SR*10, 2, SR);
    printf("wrote 3d cave\n");
    ag_reverb_free(&amb.reverb);

    ag_ambience_3d_init(&amb, SR, ag_vec3(0,0,0));
    ag_ambience_3d_preset_ocean(&amb);
    ag_ambience_3d_render(&amb, stereo, SR*10);
    ag_wav_write_f32("/tmp/ag_amb3d_ocean.wav", stereo, SR*10, 2, SR);
    printf("wrote 3d ocean\n");
    ag_reverb_free(&amb.reverb);

    ag_ambience_3d_init(&amb, SR, ag_vec3(0,0,0));
    ag_ambience_3d_preset_nexus(&amb);
    ag_ambience_3d_render(&amb, stereo, SR*10);
    ag_wav_write_f32("/tmp/ag_amb3d_nexus.wav", stereo, SR*10, 2, SR);
    printf("wrote 3d nexus\n");
    ag_reverb_free(&amb.reverb);
    free(stereo);
}

static void gen_soundscapes(void){
    printf("=== Soundscapes ===\n");
    float *stereo = (float*)malloc(sizeof(float)*SR*12*2);
    const char *scenes[] = {"classroom","grove","shore","nexus","rift","lab","festival","sanctum","alley","lighthouse"};
    for(size_t i=0;i<sizeof(scenes)/sizeof(scenes[0]);i++){
        AgSoundscapeParams p; ag_soundscape_params_for_scene(scenes[i], &p, 100+i);
        AgSoundscape ss; ag_soundscape_init(&ss, &p, SR);
        ag_soundscape_render(&ss, stereo, SR*12);
        char path[256]; snprintf(path,sizeof(path),"/tmp/ag_soundscape_%s.wav", scenes[i]);
        ag_wav_write_f32(path, stereo, SR*12, 2, SR);
        printf("wrote %s\n", path);
        ag_reverb_free(&ss.ambience_3d.reverb);
        for(int j=0;j<AG_PROC_LAYERS;j++){ ag_reverb_free(&ss.music_mixer.layers[j].reverb); ag_delay_free(&ss.music_mixer.layers[j].delay); }
    }
    free(stereo);
}

int main(void){
    printf("Generating environment/3D ambient WAVs to /tmp/\n");
    gen_3d();
    gen_water();
    gen_fire();
    gen_nature();
    gen_weather();
    gen_biomes();
    gen_ambience_3d();
    gen_soundscapes();
    printf("Done - check /tmp/ag_*.wav\n");
    return 0;
}

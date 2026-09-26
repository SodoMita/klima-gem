#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "../include/audio_gen.h"

static int failures = 0;
static void expect(int cond, const char *msg) {
    if (!cond) { fprintf(stderr,"FAIL %s\n", msg); failures++; }
}

static float rms(const float *buf, int n) {
    double acc=0;
    for(int i=0;i<n;i++) acc+= (double)buf[i]*buf[i];
    return (float)sqrt(acc / n);
}

int main(void) {
    printf("Audio Gen %s test\n", audio_gen_version());

    /* Common */
    {
        AgRng rng; ag_rng_seed(&rng, 123);
        float a = ag_rng_next_f32(&rng);
        float b = ag_rng_next_f32(&rng);
        expect(a!=b, "rng varies");
        AgScale scale; ag_scale_major(&scale);
        expect(scale.count==7, "major scale");
        int midi = ag_scale_degree_to_midi(0,60,&scale);
        expect(midi==60, "degree 0");
    }

    /* Osc */
    {
        AgOsc osc; ag_osc_init(&osc, AG_OSC_SINE, 44100);
        ag_osc_set_freq(&osc, 440);
        float sum=0;
        for(int i=0;i<100;i++) sum+= ag_osc_next(&osc);
        expect(fabsf(sum) < 20.0f, "sine approx zero mean");
    }

    /* Envelope */
    {
        AgADSR adsr = ag_adsr_pluck();
        AgEnv env; ag_env_init(&env, adsr, 44100);
        ag_env_trigger(&env);
        float v=0;
        for(int i=0;i<44100;i++) v=ag_env_next(&env);
        expect(v < 0.01f, "pluck decays");
    }

    /* Filter */
    {
        AgBiquad f; ag_biquad_init(&f);
        ag_biquad_set(&f, AG_FILTER_LP, 1000, 0.7f, 0, 44100);
        float out = ag_biquad_process(&f, 1.0f);
        expect(out != 0.0f, "biquad processes");
    }

    /* Noise */
    {
        AgNoise n; ag_noise_init(&n, 1);
        float w = ag_noise_white(&n);
        float p = ag_noise_pink(&n);
        expect(w>=-1.0f && w<=1.0f, "white range");
        expect(p>=-1.0f && p<=1.0f, "pink range");
    }

    /* SFX */
    {
        float buf[4410];
        AgSfxParams sp; ag_sfx_preset_coin(&sp);
        int got = ag_sfx_render(&sp, buf, 4410, 44100);
        expect(got>100, "sfx coin renders");
        expect(rms(buf, got) > 0.01f, "sfx audible");
    }

    /* Drums */
    {
        float buf[4410];
        AgDrumParams dp; ag_drum_params_default(&dp, AG_DRUM_KICK);
        int got = ag_drum_render(&dp, buf, 4410, 44100);
        expect(got>100, "kick renders");
        expect(rms(buf, got) > 0.01f, "kick audible");
    }

    /* FM */
    {
        AgFmVoice2 fm; ag_fm_voice2_init(&fm, 44100, 220, 2.0f);
        ag_fm_apply_preset_2op(&fm, AG_FM_PRESET_BASS);
        ag_fm_voice2_note_on(&fm, 110, 0.8f);
        float sum=0;
        for(int i=0;i<4410;i++) sum+= fabsf(ag_fm_voice2_next(&fm));
        expect(sum>1.0f, "fm bass audible");
    }

    /* Chiptune */
    {
        AgChip chip; ag_chip_init(&chip, 44100);
        ag_chip_square_note_on(&chip.sq1, 440, 0.5f, 2);
        float sum=0;
        for(int i=0;i<4410;i++) sum+= fabsf(ag_chip_next(&chip));
        expect(sum>1.0f, "chip audible");
    }

    /* Ambient */
    {
        AgDrone drone; ag_drone_init(&drone, 44100, 110);
        float sum=0;
        for(int i=0;i<4410;i++) sum+= fabsf(ag_drone_next(&drone));
        expect(sum>1.0f, "drone audible");
        AgWindGen wind; ag_wind_init(&wind, 44100);
        sum=0; for(int i=0;i<4410;i++) sum+= fabsf(ag_wind_next(&wind));
        expect(sum>0.1f, "wind audible");
    }

    /* Music box */
    {
        AgTine tine; ag_tine_init(&tine, 44100);
        ag_tine_hit(&tine, 440, 0.8f);
        float sum=0;
        for(int i=0;i<4410;i++) sum+= fabsf(ag_tine_next(&tine));
        expect(sum>1.0f, "tine audible");
        AgKarplus ks; ag_ks_init(&ks, 44100);
        ag_ks_pluck(&ks, 110, 0.5f, 0.7f);
        sum=0; for(int i=0;i<4410;i++) sum+= fabsf(ag_ks_next(&ks));
        expect(sum>1.0f, "ks audible");
        AgBell bell; ag_bell_init(&bell, 44100);
        ag_bell_hit(&bell, 440, 0.8f);
        sum=0; for(int i=0;i<4410;i++) sum+= fabsf(ag_bell_next(&bell));
        expect(sum>0.5f, "bell audible");
    }

    /* Sequencer */
    {
        AgSequencer seq; ag_seq_init(&seq, 44100, 120, 16);
        ag_seq_set_step(&seq,0,0,60,0.8f,0.8f);
        int ticked=0;
        for(int i=0;i<44100;i++) if (ag_seq_tick(&seq)) ticked++;
        expect(ticked>0, "seq ticks");
        int euclid[16]; ag_euclidean(euclid,16,5,0);
        int sum=0; for(int i=0;i<16;i++) sum+=euclid[i];
        expect(sum==5, "euclidean pulses");
    }

    /* Reverb */
    {
        AgReverb rv; ag_reverb_init(&rv, 44100);
        float out = ag_reverb_process(&rv, 1.0f);
        /* first sample may be 0 due to delay lines */
        float sum=0;
        for(int i=0;i<4410;i++) sum+= fabsf(ag_reverb_process(&rv, i==0?1.0f:0.0f));
        expect(sum>0.01f, "reverb tail");
        ag_reverb_free(&rv);
    }

    /* Delay */
    {
        AgDelay d; ag_delay_init(&d, 44100, 1000);
        ag_delay_set_delay(&d, 100);
        ag_delay_set_feedback(&d, 0.5f);
        float out = ag_delay_process(&d, 1.0f);
        float sum=out;
        for(int i=0;i<4410;i++) sum+= fabsf(ag_delay_process(&d, 0.0f));
        expect(sum>0.01f, "delay tail");
        ag_delay_free(&d);
    }

    /* Proc music */
    {
        AgProcSpec spec; ag_proc_spec_from_mood(&spec, AG_MOOD_CALM, 60, 72, 12345);
        spec.id=1;
        AgProcMusic pm; ag_proc_init(&pm, &spec, 44100);
        float buf[8820]; /* stereo 4410 frames */
        ag_proc_render(&pm, buf, 4410);
        expect(rms(buf, 8820) > 0.001f, "proc calm audible");
        AgProcMixer mixer; ag_proc_mixer_init(&mixer, 44100);
        ag_proc_mixer_transition(&mixer, &spec, 0.1f);
        ag_proc_mixer_render(&mixer, buf, 1024);
        expect(ag_proc_mixer_active(&mixer), "proc mixer active");
        for(int i=0;i<2;i++) {
            ag_reverb_free(&mixer.layers[i].reverb);
            ag_delay_free(&mixer.layers[i].delay);
        }
        ag_reverb_free(&pm.reverb);
        ag_delay_free(&pm.delay);
    }

    /* Distortion */
    {
        AgDistortion dist; ag_dist_init(&dist, 44100);
        ag_dist_set(&dist, 3.0f, 0.5f, 4000.0f);
        float out = ag_dist_process(&dist, 0.5f);
        expect(fabsf(out) > 0.01f, "distortion audible");
        AgBitcrush bc; ag_bitcrush_init(&bc, 44100);
        ag_bitcrush_set(&bc, 4, 8);
        out = ag_bitcrush_process(&bc, 0.5f);
        expect(fabsf(out) <= 1.0f, "bitcrush range");
    }

    /* Sampler */
    {
        AgSample samp; ag_sample_init(&samp);
        ag_sample_from_sine(&samp, 440, 0.1f, 44100);
        expect(samp.frames>0, "sample alloc");
        AgSamplerVoice voice; ag_sampler_voice_init(&voice, &samp);
        ag_sampler_voice_play(&voice, 0, 0.8f, 0.0f);
        float sum=0; for(int i=0;i<4410;i++) sum+=fabsf(ag_sampler_voice_next(&voice));
        expect(sum>1.0f, "sampler audible");
        ag_sample_free(&samp);
    }

    /* Formant */
    {
        AgFormantVoice fv; ag_formant_voice_init(&fv, 44100);
        ag_formant_voice_set_vowel(&fv, &AG_VOWEL_A);
        ag_formant_voice_set_freq(&fv, 110);
        float sum=0; for(int i=0;i<4410;i++) sum+=fabsf(ag_formant_voice_next(&fv));
        expect(sum>0.5f, "formant audible");
    }

    /* 3D */
    {
        AgListener lis; ag_listener_init(&lis, ag_vec3(0,0,0));
        ag_listener_set_orientation(&lis, ag_vec3(0,0,-1), ag_vec3(0,1,0));
        AgSource src; ag_source_init(&src, ag_vec3(5,0,0));
        ag_source_set_dist(&src, 1.0f, 20.0f, 1.0f, AG_DIST_INVERSE);
        float att = ag_3d_attenuation(&src, 5.0f);
        expect(att>0.1f && att<=1.0f, "3d attenuation");
        AgPanning pan = ag_3d_pan_stereo(&src, &lis);
        expect(pan.l>=-0.01f && pan.r>=-0.01f, "3d pan");
        expect(pan.l<=1.01f && pan.r<=1.01f, "3d pan range");
        AgSpatializer spat; ag_spatializer_init(&spat, 44100);
        float l,r; ag_spatializer_process(&spat, &src, &lis, 0.5f, &l, &r);
        expect(fabsf(l)>0.001f || fabsf(r)>0.001f, "spatializer audible");
    }

    /* Water */
    {
        AgOcean ocean; ag_ocean_init(&ocean, 44100);
        float sum=0; for(int i=0;i<4410;i++) sum+=fabsf(ag_ocean_next(&ocean));
        expect(sum>0.5f, "ocean audible");
        AgRiver river; ag_river_init(&river, 44100);
        sum=0; for(int i=0;i<4410;i++) sum+=fabsf(ag_river_next(&river));
        expect(sum>0.5f, "river audible");
        AgDrip drip; ag_drip_init(&drip, 44100);
        ag_drip_trigger(&drip, 1200, 0.8f);
        sum=0; for(int i=0;i<4410;i++) sum+=fabsf(ag_drip_next(&drip));
        expect(sum>0.1f, "drip audible");
    }

    /* Fire */
    {
        AgFire fire; ag_fire_init(&fire, 44100);
        float sum=0; for(int i=0;i<4410;i++) sum+=fabsf(ag_fire_next(&fire));
        expect(sum>0.5f, "fire audible");
    }

    /* Nature */
    {
        AgBird bird; ag_bird_init(&bird, 44100, 0);
        ag_bird_trigger(&bird);
        float sum=0; for(int i=0;i<4410;i++) sum+=fabsf(ag_bird_next(&bird));
        expect(sum>0.1f, "bird audible");
        AgCricket cricket; ag_cricket_init(&cricket, 44100);
        sum=0; for(int i=0;i<4410;i++) sum+=fabsf(ag_cricket_next(&cricket));
        expect(sum>0.05f, "cricket audible");
    }

    /* Weather */
    {
        AgWeatherMixer wm; ag_weather_mixer_init(&wm, 44100);
        ag_weather_mixer_set(&wm, AG_WEATHER_RAIN_MEDIUM, 0.7f);
        float sum=0; for(int i=0;i<4410;i++){ float l,r; ag_weather_mixer_next_stereo(&wm,&l,&r); sum+=fabsf(l)+fabsf(r); }
        expect(sum>0.5f, "weather rain audible");
        ag_weather_mixer_set(&wm, AG_WEATHER_THUNDERSTORM, 0.8f);
        sum=0; for(int i=0;i<44100;i++){ float l,r; ag_weather_mixer_next_stereo(&wm,&l,&r); sum+=fabsf(l)+fabsf(r); }
        expect(sum>0.5f, "thunderstorm audible");
    }

    /* Biome */
    {
        AgBiomeParams bp; ag_biome_params_default(&bp, AG_BIOME_FOREST);
        bp.seed=123;
        AgBiome biome; ag_biome_init(&biome, &bp, 44100);
        float buf[44100*2]; ag_biome_render(&biome, buf, 4410);
        expect(rms(buf, 8820)>0.0005f, "biome forest audible");
    }

    /* 3D Ambience */
    {
        AgAmbience3D amb; ag_ambience_3d_init(&amb, 44100, ag_vec3(0,0,0));
        ag_ambience_3d_preset_forest(&amb);
        float buf[44100*2]; ag_ambience_3d_render(&amb, buf, 4410);
        expect(rms(buf, 8820)>0.0005f, "3d forest audible");
        ag_reverb_free(&amb.reverb);
    }

    /* Soundscape */
    {
        AgSoundscapeParams ssp; ag_soundscape_params_for_scene("grove",&ssp, 42);
        AgSoundscape ss; ag_soundscape_init(&ss, &ssp, 44100);
        float buf[44100*2]; ag_soundscape_render(&ss, buf, 4410);
        expect(rms(buf, 8820)>0.0005f, "soundscape grove audible");
        ag_reverb_free(&ss.ambience_3d.reverb);
        for(int i=0;i<AG_PROC_LAYERS;i++){ ag_reverb_free(&ss.music_mixer.layers[i].reverb); ag_delay_free(&ss.music_mixer.layers[i].delay); }
    }

    /* WAV */
    {
        float buf[4410];
        for(int i=0;i<4410;i++) buf[i]= sinf(i*0.1f)*0.5f;
        int ok = ag_wav_write_f32("/tmp/test_audio_gen.wav", buf, 4410, 1, 44100);
        expect(ok, "wav write");
        AgWavInfo info;
        ok = ag_wav_read_info("/tmp/test_audio_gen.wav", &info);
        expect(ok && info.frames==4410, "wav read info");
    }

    if (failures) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    printf("all audio_gen tests ok\n");
    return 0;
}

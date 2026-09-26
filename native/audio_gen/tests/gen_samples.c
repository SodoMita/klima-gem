/* Generate example WAV files for audition */
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include "../include/audio_gen.h"

#define SR 44100

static void gen_sfx(void) {
    float buf[SR*2];
    AgSfxParams p;
    struct { const char *name; void (*preset)(AgSfxParams*); } presets[] = {
        {"coin", ag_sfx_preset_coin},
        {"laser", ag_sfx_preset_laser},
        {"explosion", ag_sfx_preset_explosion},
        {"powerup", ag_sfx_preset_powerup},
        {"hit", ag_sfx_preset_hit},
        {"jump", ag_sfx_preset_jump},
        {"blip", ag_sfx_preset_blip},
        {"click", ag_sfx_preset_click},
        {"buzz", ag_sfx_preset_buzz},
        {"whoosh", ag_sfx_preset_whoosh},
        {"open", ag_sfx_preset_open},
        {"close", ag_sfx_preset_close},
    };
    for (size_t i=0;i<sizeof(presets)/sizeof(presets[0]);i++) {
        presets[i].preset(&p);
        int frames = ag_sfx_render(&p, buf, SR*2, SR);
        char path[256]; snprintf(path,sizeof(path),"/tmp/ag_sfx_%s.wav", presets[i].name);
        ag_wav_write_f32(path, buf, frames, 1, SR);
        printf("wrote %s (%d frames)\n", path, frames);
    }
}

static void gen_drums(void) {
    float buf[SR];
    AgDrumType types[] = {AG_DRUM_KICK, AG_DRUM_SNARE, AG_DRUM_HIHAT_CLOSED, AG_DRUM_HIHAT_OPEN, AG_DRUM_CLAP, AG_DRUM_TOM_LOW, AG_DRUM_TOM_MID, AG_DRUM_TOM_HIGH, AG_DRUM_RIM, AG_DRUM_COWBELL, AG_DRUM_CYMBAL};
    const char *names[] = {"kick","snare","hihat_closed","hihat_open","clap","tom_low","tom_mid","tom_high","rim","cowbell","cymbal"};
    for (size_t i=0;i<sizeof(types)/sizeof(types[0]);i++) {
        AgDrumParams dp; ag_drum_params_default(&dp, types[i]);
        int frames = ag_drum_render(&dp, buf, SR, SR);
        char path[256]; snprintf(path,sizeof(path),"/tmp/ag_drum_%s.wav", names[i]);
        ag_wav_write_f32(path, buf, frames, 1, SR);
        printf("wrote %s\n", path);
    }
}

static void gen_fm(void) {
    float buf[SR*2];
    AgFmPreset presets[] = {AG_FM_PRESET_BASS, AG_FM_PRESET_LEAD, AG_FM_PRESET_PAD, AG_FM_PRESET_BELL, AG_FM_PRESET_EPIANO, AG_FM_PRESET_BRASS};
    const char *names[] = {"bass","lead","pad","bell","epiano","brass"};
    for (size_t i=0;i<sizeof(presets)/sizeof(presets[0]);i++) {
        AgFmVoice2 v; ag_fm_voice2_init(&v, SR, 220, 2.0f);
        ag_fm_apply_preset_2op(&v, presets[i]);
        ag_fm_voice2_note_on(&v, 110, 0.8f);
        for (int s=0;s<SR*2;s++) {
            if (s==SR) ag_fm_voice2_note_off(&v);
            buf[s]=ag_fm_voice2_next(&v);
        }
        char path[256]; snprintf(path,sizeof(path),"/tmp/ag_fm_%s.wav", names[i]);
        ag_wav_write_f32(path, buf, SR*2, 1, SR);
        printf("wrote %s\n", path);
    }
}

static void gen_ambient(void) {
    float buf[SR*4];
    AgDrone drone; ag_drone_init(&drone, SR, 55);
    for (int i=0;i<SR*4;i++) buf[i]=ag_drone_next(&drone);
    ag_wav_write_f32("/tmp/ag_ambient_drone.wav", buf, SR*4, 1, SR);
    printf("wrote drone\n");

    AgWindGen wind; ag_wind_init(&wind, SR);
    ag_wind_set_strength(&wind, 0.6f);
    for (int i=0;i<SR*4;i++) buf[i]=ag_wind_next(&wind);
    ag_wav_write_f32("/tmp/ag_ambient_wind.wav", buf, SR*4, 1, SR);
    printf("wrote wind\n");

    AgGranularPad gp; ag_granular_init(&gp, SR, 110);
    for (int i=0;i<SR*4;i++) buf[i]=ag_granular_next(&gp);
    ag_wav_write_f32("/tmp/ag_ambient_granular.wav", buf, SR*4, 1, SR);
    printf("wrote granular\n");
}

static void gen_musicbox(void) {
    float buf[SR*6];
    AgMusicBox mb; ag_musicbox_init(&mb, SR);
    ag_musicbox_add_note(&mb, 0.0f, 60, 0.8f);
    ag_musicbox_add_note(&mb, 0.5f, 64, 0.7f);
    ag_musicbox_add_note(&mb, 1.0f, 67, 0.8f);
    ag_musicbox_add_note(&mb, 1.5f, 72, 0.9f);
    ag_musicbox_add_note(&mb, 2.0f, 67, 0.7f);
    ag_musicbox_add_note(&mb, 2.5f, 64, 0.7f);
    ag_musicbox_add_note(&mb, 3.0f, 60, 0.8f);
    for (int i=0;i<SR*6;i++) buf[i]=ag_musicbox_next(&mb);
    ag_wav_write_f32("/tmp/ag_musicbox.wav", buf, SR*6, 1, SR);
    printf("wrote musicbox\n");

    AgBell bell; ag_bell_init(&bell, SR);
    ag_bell_hit(&bell, 440, 0.8f);
    for (int i=0;i<SR*3;i++) buf[i]=ag_bell_next(&bell);
    ag_wav_write_f32("/tmp/ag_bell.wav", buf, SR*3, 1, SR);
    printf("wrote bell\n");

    AgKarplus ks; ag_ks_init(&ks, SR);
    ag_ks_pluck(&ks, 110, 0.5f, 0.8f);
    for (int i=0;i<SR*3;i++) buf[i]=ag_ks_next(&ks);
    ag_wav_write_f32("/tmp/ag_karplus.wav", buf, SR*3, 1, SR);
    printf("wrote karplus\n");
}

static void gen_proc(void) {
    float buf[SR*10*2];
    AgMood moods[] = {AG_MOOD_CALM, AG_MOOD_TENSE, AG_MOOD_LOFI, AG_MOOD_CHIPTUNE, AG_MOOD_AMBIENT, AG_MOOD_RIFT};
    for (size_t i=0;i<sizeof(moods)/sizeof(moods[0]);i++) {
        AgProcSpec spec; ag_proc_spec_from_mood(&spec, moods[i], 60, 90, 12345+i);
        spec.id=i+1;
        AgProcMusic pm; ag_proc_init(&pm, &spec, SR);
        ag_proc_render(&pm, buf, SR*10);
        char path[256]; snprintf(path,sizeof(path),"/tmp/ag_proc_%s.wav", ag_mood_to_string(moods[i]));
        ag_wav_write_f32(path, buf, SR*10, 2, SR);
        printf("wrote %s\n", path);
        ag_reverb_free(&pm.reverb);
        ag_delay_free(&pm.delay);
    }
}

static void gen_chiptune(void) {
    float buf[SR*8*2];
    AgChipSequencer seq; ag_chip_seq_init(&seq, SR, 120);
    AgChipPattern pat; ag_chip_pattern_init(&pat);
    /* simple pattern */
    ag_chip_pattern_set(&pat, 0, 60, 48, 36, 0);
    ag_chip_pattern_set(&pat, 2, 62, 50, 38, 0);
    ag_chip_pattern_set(&pat, 4, 64, 52, 40, 1);
    ag_chip_pattern_set(&pat, 6, 65, 53, 41, 0);
    ag_chip_pattern_set(&pat, 8, 67, 55, 43, 0);
    ag_chip_pattern_set(&pat,10, 65, 53, 41, 0);
    ag_chip_pattern_set(&pat,12, 64, 52, 40, 1);
    ag_chip_pattern_set(&pat,14, 62, 50, 38, 0);
    ag_chip_seq_set_pattern(&seq, &pat);
    for (int i=0;i<SR*8;i++) {
        float s = ag_chip_seq_next(&seq);
        buf[i*2]=s; buf[i*2+1]=s;
    }
    ag_wav_write_f32("/tmp/ag_chiptune.wav", buf, SR*8, 2, SR);
    printf("wrote chiptune\n");
}

int main(void) {
    printf("Generating sample WAVs to /tmp/\n");
    gen_sfx();
    gen_drums();
    gen_fm();
    gen_ambient();
    gen_musicbox();
    gen_proc();
    gen_chiptune();
    printf("Done\n");
    return 0;
}

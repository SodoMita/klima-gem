#ifndef AG_SFX_H
#define AG_SFX_H

#include "ag_common.h"
#include "ag_osc.h"
#include "ag_envelope.h"
#include "ag_filter.h"

#ifdef __cplusplus
extern "C" {
#endif

/* sfxr-inspired SFX synth but cleaner API */

typedef enum {
    AG_SFX_SINE = 0,
    AG_SFX_SQUARE,
    AG_SFX_SAW,
    AG_SFX_TRI,
    AG_SFX_NOISE,
    AG_SFX_SINE_SQUARE_MIX
} AgSfxWave;

typedef struct AgSfxParams {
    AgSfxWave wave;

    /* Frequency */
    float base_freq;      /* Hz */
    float freq_ramp;      /* Hz/sec - linear slide */
    float freq_dramp;     /* Hz/sec^2 - curve */
    float vib_strength;   /* Hz */
    float vib_speed;      /* Hz */
    float duty;           /* 0..1 for square */
    float duty_ramp;      /* per sec */

    /* Envelope - AR with sustain punch */
    float attack;         /* sec */
    float sustain;        /* sec */
    float punch;          /* sustain punch 0..1 */
    float decay;          /* sec */

    /* Filter */
    int filter_on;
    AgFilterType filter_type;
    float lpf_freq;
    float lpf_ramp;
    float lpf_resonance;
    float hpf_freq;
    float hpf_ramp;

    /* Phaser, repeat, etc */
    float phaser_offset;
    float phaser_ramp;
    float repeat_speed;   /* sec between repeats, 0 = no repeat */
    float arp_speed;      /* sec */
    float arp_mod;        /* semitones */

    /* Gain */
    float gain;           /* 0..1 */

    uint64_t seed;
} AgSfxParams;

typedef struct AgSfxVoice {
    AgSfxParams params;
    AgOsc osc;
    AgOsc vib_osc;
    AgBiquad lpf;
    AgBiquad hpf;
    AgEnvAR env;
    AgRng rng;
    double t;
    double total_dur;
    float base_freq;
    float current_duty;
    int active;
    double phaser_phase;
    double repeat_t;
    int repeat_count;
    double arp_t;
    int arp_stage;
} AgSfxVoice;

void ag_sfx_params_init(AgSfxParams *p, uint64_t seed);

/* Presets - fill params with classic sounds */
void ag_sfx_preset_coin(AgSfxParams *p);
void ag_sfx_preset_laser(AgSfxParams *p);
void ag_sfx_preset_explosion(AgSfxParams *p);
void ag_sfx_preset_powerup(AgSfxParams *p);
void ag_sfx_preset_hit(AgSfxParams *p);
void ag_sfx_preset_jump(AgSfxParams *p);
void ag_sfx_preset_blip(AgSfxParams *p);
void ag_sfx_preset_click(AgSfxParams *p);
void ag_sfx_preset_sweep(AgSfxParams *p, float from_freq, float to_freq, float dur);
void ag_sfx_preset_chime(AgSfxParams *p, int tone_count, float base_freq);
void ag_sfx_preset_buzz(AgSfxParams *p);
void ag_sfx_preset_whoosh(AgSfxParams *p);
void ag_sfx_preset_open(AgSfxParams *p);
void ag_sfx_preset_close(AgSfxParams *p);

/* Voice lifecycle */
void ag_sfx_voice_init(AgSfxVoice *v, const AgSfxParams *p, float sr);
int ag_sfx_voice_active(const AgSfxVoice *v);
float ag_sfx_voice_next(AgSfxVoice *v);

/* Render whole SFX into buffer (mono float) */
int ag_sfx_render(const AgSfxParams *params, float *out, int max_frames, float sr);
int ag_sfx_render_stereo(const AgSfxParams *params, float *interleaved_stereo, int max_frames, float sr);

/* High-level helpers - render directly with preset */
int ag_sfx_render_preset_coin(float *out, int max_frames, float sr);
int ag_sfx_render_preset_laser(float *out, int max_frames, float sr);
int ag_sfx_render_preset_explosion(float *out, int max_frames, float sr);

#ifdef __cplusplus
}
#endif

#endif

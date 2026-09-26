#ifndef AG_WATER_H
#define AG_WATER_H

#include "ag_common.h"
#include "ag_osc.h"
#include "ag_filter.h"
#include "ag_noise.h"
#include "ag_envelope.h"

#ifdef __cplusplus
extern "C" {
#endif

/* High-quality water - multi-layer physical modeling */

/* Ocean: deep rumble + mid swell + high foam + crash + spray */
typedef struct AgOcean {
    AgNoise noise_mid;
    AgNoise noise_low;
    AgNoise noise_high;
    AgBiquad lp_low;      /* 120 Hz deep */
    AgBiquad lp_mid;      /* 800 Hz body */
    AgBiquad lp_foam;     /* 3500 Hz foam */
    AgBiquad hp_spray;    /* 2000 Hz spray */
    AgBiquad bp_crash;    /* 250-400 Hz crash */
    AgBiquad bp_splash;   /* 1200 Hz splash */
    AgOsc swell_lfo;      /* 0.07 Hz main swell */
    AgOsc swell_lfo2;     /* 0.09 Hz secondary */
    AgOsc foam_lfo;       /* 0.31 Hz foam variation */
    AgOsc crash_lfo;      /* 0.15 Hz */
    AgOsc spray_lfo;      /* 0.5 Hz */
    AgEnv crash_env;      /* crash burst envelope */
    AgRng rng;
    double sr;
    float gain;
    float swell_strength;
    float crash_chance;
    double crash_timer;
    float base_freq;
    float crash_env_val;
    double crash_decay;
    float low_gain;
    float mid_gain;
    float high_gain;
    float foam_gain;
    /* stereo decorrelation */
    float decor_l;
    float decor_r;
} AgOcean;

void ag_ocean_init(AgOcean *o, double sr);
void ag_ocean_set(AgOcean *o, float gain, float swell_strength);
float ag_ocean_next(AgOcean *o);
void ag_ocean_next_stereo(AgOcean *o, float *l, float *r);

/* River: deep flow + mid turbulence + surface hiss + bubbles */
typedef struct AgRiver {
    AgNoise noise_deep;
    AgNoise noise_mid;
    AgNoise noise_surf;
    AgBiquad lp_deep;     /* 350 Hz */
    AgBiquad lp_mid;      /* 1200 Hz */
    AgBiquad hp_surf;     /* 1800 Hz */
    AgBiquad bp_bubble;   /* 800 Hz bubble */
    AgOsc flow_lfo;       /* 0.3 Hz */
    AgOsc flow_lfo2;      /* 0.17 Hz */
    AgOsc turb_lfo;       /* 1.1 Hz */
    AgOsc hiss_lfo;       /* 2.3 Hz */
    AgRng rng;
    double sr;
    float gain;
    float turbulence;
    float bubble_timer;
    float bubble_next;
    float deep_gain;
    float mid_gain;
    float surf_gain;
} AgRiver;

void ag_river_init(AgRiver *r, double sr);
float ag_river_next(AgRiver *r);
void ag_river_next_stereo(AgRiver *r, float *l, float *r_out);

/* Stream: river + sparkle droplets + light */
typedef struct AgStream {
    AgRiver river;
    AgBiquad sparkle_bp;  /* 3500 Hz */
    AgBiquad sparkle_bp2; /* 5000 Hz */
    AgOsc sparkle_lfo;
    AgRng rng;
    float sparkle_chance;
    float droplet_timer;
    float next_droplet;
    AgEnv droplet_env;
    AgOsc droplet_osc;
    AgBiquad droplet_bp;
} AgStream;

void ag_stream_init(AgStream *s, double sr);
float ag_stream_next(AgStream *s);
void ag_stream_next_stereo(AgStream *s, float *l, float *r);

/* Waterfall: low roar + mid roar + high spray + mist */
typedef struct AgWaterfall {
    AgNoise noise_low;
    AgNoise noise_mid;
    AgNoise noise_high;
    AgBiquad lp_low;      /* 150 Hz */
    AgBiquad lp_mid;      /* 800 Hz */
    AgBiquad lp_high;     /* 3000 Hz */
    AgBiquad hp_mist;     /* 1000 Hz */
    AgBiquad bp_roar;     /* 200 Hz */
    AgOsc roar_lfo;       /* 0.12 Hz */
    AgOsc roar_lfo2;      /* 0.07 Hz */
    AgOsc mist_lfo;       /* 0.9 Hz */
    AgRng rng;
    double sr;
    float gain;
    float roar;
    float mist_gain;
    float low_gain;
} AgWaterfall;

void ag_waterfall_init(AgWaterfall *wf, double sr);
float ag_waterfall_next(AgWaterfall *wf);
void ag_waterfall_next_stereo(AgWaterfall *wf, float *l, float *r);

/* Drip: modal synthesis - 3 resonant modes + ripple + early reflection */
typedef struct AgDrip {
    AgOsc osc_main;
    AgOsc osc_mode2;
    AgOsc osc_mode3;
    AgEnv env_main;
    AgEnv env_ripple;
    AgBiquad filter_main;
    AgBiquad filter_mode2;
    AgBiquad filter_mode3;
    AgBiquad hp_click;    /* high click */
    AgRng rng;
    double sr;
    double timer;
    double next_drip_time;
    float gain;
    int active;
    float drip_freq;
    float ripple_freq;
    float decay;
    float early_delay[64]; /* tiny delay for reflection */
    int early_pos;
} AgDrip;

void ag_drip_init(AgDrip *d, double sr);
void ag_drip_trigger(AgDrip *d, float freq, float gain);
float ag_drip_next(AgDrip *d);
void ag_drip_auto(AgDrip *d, float density);
void ag_drip_next_stereo(AgDrip *d, float *l, float *r);

/* Bubbles: up to 4 overlapping bubbles with wobble and formant */
#define AG_BUBBLES_MAX_VOICES 4
typedef struct AgBubbleVoice {
    AgOsc osc;
    AgEnv env;
    AgBiquad formant;
    AgOsc wobble_lfo;
    float freq;
    float target_freq;
    float gain;
    int active;
    double age;
} AgBubbleVoice;

typedef struct AgBubbles {
    AgRng rng;
    AgBubbleVoice voices[AG_BUBBLES_MAX_VOICES];
    double sr;
    double timer;
    double next_bubble;
    float gain;
    float rate;
    float size_var;
} AgBubbles;

void ag_bubbles_init(AgBubbles *b, double sr);
float ag_bubbles_next(AgBubbles *b);
void ag_bubbles_next_stereo(AgBubbles *b, float *l, float *r);
void ag_bubbles_set_rate(AgBubbles *b, float rate);

/* Underwater: muffled river + pressure + bubbles + low rumble */
typedef struct AgUnderwaterAmbience {
    AgRiver base;
    AgBiquad muffle_lp;   /* 600 Hz with resonance */
    AgBiquad muffle_lp2;  /* 300 Hz */
    AgOsc pressure_lfo;   /* 0.08 Hz */
    AgOsc pressure_lfo2;  /* 0.13 Hz */
    AgOsc sway_lfo;       /* 0.05 Hz */
    AgBubbles bubbles;
    AgNoise rumble_noise;
    AgBiquad rumble_lp;
    double sr;
    float gain;
    float pressure;
} AgUnderwaterAmbience;

void ag_underwater_amb_init(AgUnderwaterAmbience *uw, double sr);
float ag_underwater_amb_next(AgUnderwaterAmbience *uw);
void ag_underwater_amb_next_stereo(AgUnderwaterAmbience *uw, float *l, float *r);

#ifdef __cplusplus
}
#endif

#endif

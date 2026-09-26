#ifndef AG_FIRE_H
#define AG_FIRE_H

#include "ag_common.h"
#include "ag_noise.h"
#include "ag_filter.h"
#include "ag_osc.h"
#include "ag_envelope.h"

#ifdef __cplusplus
extern "C" {
#endif

/* High-quality fire - multi-layer + flame licks + velvet crackle */

typedef struct AgFire {
    AgNoise noise_low;    /* brown low rumble */
    AgNoise noise_mid;    /* pink mid body */
    AgNoise noise_high;   /* white high hiss */
    AgNoise noise_crackle;
    AgBiquad lp_rumble;   /* 180 Hz */
    AgBiquad lp_body;     /* 2200 Hz */
    AgBiquad lp_body2;    /* 1200 Hz */
    AgBiquad hp_hiss;     /* 3000 Hz */
    AgBiquad bp_crackle;  /* 900 Hz */
    AgBiquad bp_crackle2; /* 3200 Hz */
    AgBiquad bp_lick;     /* 600 Hz flame lick */
    AgRng rng;
    AgOsc flicker_lfo;    /* 8 Hz */
    AgOsc flicker_lfo2;   /* 11.7 Hz */
    AgOsc flicker_lfo3;   /* 5.3 Hz */
    AgOsc lick_lfo;       /* 1.2 Hz */
    AgOsc hiss_lfo;       /* 14 Hz */
    AgEnv lick_env;
    double sr;
    float gain;
    float crackle_density;
    float base_intensity;
    double timer;
    double lick_timer;
    double next_lick;
    float lick_gain;
    float rumble_gain;
    float body_gain;
    float hiss_gain;
    /* stereo */
    float decor;
} AgFire;

void ag_fire_init(AgFire *f, double sr);
void ag_fire_set(AgFire *f, float intensity, float crackle_density);
float ag_fire_next(AgFire *f);
void ag_fire_next_stereo(AgFire *f, float *l, float *r);

typedef struct AgFireplace {
    AgFire fire;
    AgBiquad room_lp;     /* 1100 Hz room */
    AgBiquad room_lp2;    /* 300 Hz */
    AgBiquad room_bp;     /* 250 Hz resonance */
    AgOsc room_lfo;       /* 0.21 Hz */
    AgOsc room_lfo2;      /* 0.07 Hz */
    float room_gain;
    float room_mix;
} AgFireplace;

void ag_fireplace_init(AgFireplace *fp, double sr);
float ag_fireplace_next(AgFireplace *fp);
void ag_fireplace_next_stereo(AgFireplace *fp, float *l, float *r);

typedef struct AgTorch {
    AgFire fire;
    AgOsc wind_lfo;       /* 1.2 Hz */
    AgOsc wind_lfo2;      /* 0.8 Hz */
    AgBiquad wind_bp;
    float wind_amount;
} AgTorch;

void ag_torch_init(AgTorch *t, double sr);
float ag_torch_next(AgTorch *t);
void ag_torch_next_stereo(AgTorch *t, float *l, float *r);

typedef struct AgBonfire {
    AgFire fire;
    AgNoise low_rumble;
    AgNoise mid_rumble;
    AgBiquad rumble_lp;   /* 120 Hz */
    AgBiquad rumble_lp2;  /* 60 Hz */
    AgBiquad rumble_bp;   /* 80 Hz */
    AgOsc rumble_lfo;     /* 0.15 Hz */
    AgOsc ember_lfo;      /* 0.5 Hz */
    float rumble_gain;
    float ember_gain;
} AgBonfire;

void ag_bonfire_init(AgBonfire *bf, double sr);
float ag_bonfire_next(AgBonfire *bf);
void ag_bonfire_next_stereo(AgBonfire *bf, float *l, float *r);

#ifdef __cplusplus
}
#endif

#endif

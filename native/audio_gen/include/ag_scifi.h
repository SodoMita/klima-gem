#ifndef AG_SCIFI_H
#define AG_SCIFI_H

#include "ag_common.h"
#include "ag_osc.h"
#include "ag_envelope.h"
#include "ag_filter.h"
#include "ag_noise.h"
#include "ag_delay.h"
#include "ag_reverb.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Sci-fi procedural SFX: laser, plasma, warp, drone, force field, glitch, hologram, etc.
 * HQ: bandlimited osc, biquad HQ, dc_block, tanh, oversample where needed
 */

typedef struct AgLaser {
    double sr;
    float gain;
    AgOsc osc;
    AgOsc osc2;
    AgBiquad filter;
    AgBiquad filter2;
    AgEnv env;
    AgDCBlock dc;
    AgRng rng;
    int active;
    double t;
    float start_freq;
    float end_freq;
    float duration;
} AgLaser;

void ag_laser_init(AgLaser *l, double sr);
void ag_laser_trigger(AgLaser *l, float start_freq, float end_freq, float duration, float vel);
float ag_laser_next(AgLaser *l);
int ag_laser_active(const AgLaser *l);

typedef struct AgPlasma {
    double sr;
    float gain;
    AgOsc carrier;
    AgOsc mod;
    AgOsc mod2;
    AgBiquad bp;
    AgBiquad lp;
    AgEnv env;
    AgDCBlock dc;
    AgRng rng;
    int active;
    double t;
} AgPlasma;

void ag_plasma_init(AgPlasma *p, double sr);
void ag_plasma_trigger(AgPlasma *p, float base_freq, float intensity, float duration);
float ag_plasma_next(AgPlasma *p);
int ag_plasma_active(const AgPlasma *p);

typedef struct AgWarp {
    double sr;
    float gain;
    AgOsc osc;
    AgOsc lfo;
    AgOsc lfo2;
    AgBiquad lp;
    AgBiquad hp;
    AgBiquad bp;
    AgEnv env;
    AgDCBlock dc;
    int active;
    double t;
    float depth;
} AgWarp;

void ag_warp_init(AgWarp *w, double sr);
void ag_warp_trigger(AgWarp *w, float duration, float depth, float vel);
float ag_warp_next(AgWarp *w);
int ag_warp_active(const AgWarp *w);

typedef struct AgScifiDrone {
    double sr;
    float gain;
    AgOsc osc1, osc2, osc3, osc4;
    AgBiquad filter;
    AgBiquad filter2;
    AgBiquad notch;
    AgLFO lfo;
    AgLFO lfo2;
    AgNoise noise;
    AgDCBlock dc;
    float detune;
    float shimmer;
} AgScifiDrone;

void ag_scifi_drone_init(AgScifiDrone *d, double sr, float base_freq);
void ag_scifi_drone_set_freq(AgScifiDrone *d, float freq);
float ag_scifi_drone_next(AgScifiDrone *d);
void ag_scifi_drone_next_stereo(AgScifiDrone *d, float *l, float *r);

typedef struct AgForceField {
    double sr;
    float gain;
    AgOsc osc1, osc2;
    AgBiquad bp1, bp2;
    AgBiquad lp;
    AgLFO lfo;
    AgLFO lfo2;
    AgNoise noise;
    AgDCBlock dc;
    float buzz;
} AgForceField;

void ag_forcefield_init(AgForceField *ff, double sr, float base_freq);
float ag_forcefield_next(AgForceField *ff);
void ag_forcefield_next_stereo(AgForceField *ff, float *l, float *r);

typedef struct AgGlitch {
    double sr;
    float gain;
    AgNoise noise;
    AgBiquad bp;
    AgBiquad hp;
    AgRng rng;
    AgEnv env;
    AgOsc stutter_lfo;
    double timer;
    double next_glitch;
    float buf[1024];
    int buf_pos;
    int active;
    AgDCBlock dc;
} AgGlitch;

void ag_glitch_init(AgGlitch *g, double sr);
float ag_glitch_next(AgGlitch *g);
void ag_glitch_trigger(AgGlitch *g, float intensity);
void ag_glitch_next_stereo(AgGlitch *g, float *l, float *r);

typedef struct AgHologram {
    double sr;
    float gain;
    AgOsc osc1, osc2;
    AgOsc mod;
    AgBiquad bp;
    AgBiquad lp;
    AgBiquad hp;
    AgLFO lfo;
    AgEnv env;
    AgDCBlock dc;
    int active;
} AgHologram;

void ag_hologram_init(AgHologram *h, double sr);
void ag_hologram_trigger(AgHologram *h, float freq, float duration);
float ag_hologram_next(AgHologram *h);
int ag_hologram_active(const AgHologram *h);

typedef struct AgScifiEngine {
    double sr;
    float gain;
    AgOsc osc1, osc2;
    AgBiquad lp;
    AgBiquad bp;
    AgLFO rumble_lfo;
    AgNoise noise;
    AgDCBlock dc;
    float thrust; /* 0..1 */
} AgScifiEngine;

void ag_scifi_engine_init(AgScifiEngine *e, double sr, float base_freq);
void ag_scifi_engine_set_thrust(AgScifiEngine *e, float thrust);
float ag_scifi_engine_next(AgScifiEngine *e);

#ifdef __cplusplus
}
#endif

#endif

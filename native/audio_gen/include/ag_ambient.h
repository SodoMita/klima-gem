#ifndef AG_AMBIENT_H
#define AG_AMBIENT_H

#include "ag_common.h"
#include "ag_osc.h"
#include "ag_filter.h"
#include "ag_noise.h"
#include "ag_envelope.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct AgDrone {
    AgOsc osc1, osc2, osc3, osc4;
    AgBiquad filter, filter2;
    AgLFO lfo, lfo2;
    AgNoise noise, noise2;
    AgDCBlock dc;
    float gain;
    double sr;
    float detune;
} AgDrone;

void ag_drone_init(AgDrone *d, double sr, float base_freq);
void ag_drone_set_freq(AgDrone *d, float freq);
float ag_drone_next(AgDrone *d);

typedef struct AgWindGen {
    AgNoise noise, noise2;
    AgBiquad lp1, lp2, lp3;
    AgOnePole smooth;
    AgLFO gust_lfo, gust_lfo2;
    float gain;
    double sr;
    float gust_strength;
} AgWindGen;

void ag_wind_init(AgWindGen *w, double sr);
void ag_wind_set_strength(AgWindGen *w, float strength);
float ag_wind_next(AgWindGen *w);

typedef struct AgRain {
    AgNoise noise, noise2;
    AgBiquad bp, bp2, lp;
    AgRng rng;
    double sr;
    float density;
    float gain;
    double timer;
} AgRain;

void ag_rain_init(AgRain *r, double sr);
void ag_rain_set_density(AgRain *r, float density);
float ag_rain_next(AgRain *r);

#define AG_GRAIN_MAX 32
#define AG_GRAIN_LEN 1024

typedef struct AgGrain {
    float buf[AG_GRAIN_LEN];
    int pos;
    int len;
    float pan_l, pan_r;
    float gain;
    int active;
    double env_phase;
} AgGrain;

typedef struct AgGranularPad {
    AgGrain grains[AG_GRAIN_MAX];
    AgRng rng;
    double sr;
    float base_freq;
    float spread;
    float grain_rate;
    double timer;
    float gain;
    AgBiquad filter, filter2;
    AgLFO lfo;
} AgGranularPad;

void ag_granular_init(AgGranularPad *gp, double sr, float base_freq);
void ag_granular_set(AgGranularPad *gp, float freq, float spread, float rate);
float ag_granular_next(AgGranularPad *gp);
void ag_granular_next_stereo(AgGranularPad *gp, float *l, float *r);

typedef struct AgShimmer {
    AgOsc osc;
    AgBiquad filter, filter2;
    float feedback;
    float shift;
    float buf[44100];
    int buf_pos;
    float read_pos;
    double sr;
    float gain;
} AgShimmer;

void ag_shimmer_init(AgShimmer *sh, double sr, float base_freq);
float ag_shimmer_next(AgShimmer *sh, float in);

typedef struct AgUnderwater {
    AgBiquad lp, lp2, hp;
    AgOsc lfo, lfo2;
    AgDCBlock dc;
    float gain;
    double sr;
} AgUnderwater;

void ag_underwater_init(AgUnderwater *uw, double sr);
float ag_underwater_process(AgUnderwater *uw, float in);

#ifdef __cplusplus
}
#endif

#endif

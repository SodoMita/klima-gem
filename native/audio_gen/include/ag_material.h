#ifndef AG_MATERIAL_H
#define AG_MATERIAL_H

#include "ag_common.h"
#include "ag_osc.h"
#include "ag_envelope.h"
#include "ag_filter.h"
#include "ag_noise.h"
#include "ag_reverb.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Procedural material / Foley generators: sand, wood/log, metal, stone, glass, shimmer
 * All HQ: bandlimited osc, biquad HQ, dc_block, tanh soft clip, granular grains
 */

/* ---------- Sand ---------- */
#define AG_SAND_GRAINS 24
#define AG_SAND_GRAIN_LEN 256

typedef struct AgSandGrain {
    float buf[AG_SAND_GRAIN_LEN];
    int pos;
    int len;
    float gain;
    float pan_l, pan_r;
    int active;
    AgBiquad bp;
} AgSandGrain;

typedef struct AgSand {
    double sr;
    float gain;
    float density;      /* 0..1 how much rustle */
    float brightness;   /* 0..1 */
    AgNoise noise;
    AgNoise noise2;
    AgRng rng;
    AgBiquad lp;
    AgBiquad hp;
    AgBiquad bp_mid;
    AgBiquad presence;
    AgSandGrain grains[AG_SAND_GRAINS];
    double timer;
    double grain_interval;
    /* footstep */
    AgEnv foot_env;
    AgBiquad foot_lp;
    AgBiquad foot_bp;
    int foot_active;
    float foot_gain;
    AgDCBlock dc;
} AgSand;

void ag_sand_init(AgSand *s, double sr);
void ag_sand_set(AgSand *s, float density, float brightness, float gain);
float ag_sand_next(AgSand *s);
void ag_sand_next_stereo(AgSand *s, float *l, float *r);
void ag_sand_footstep_trigger(AgSand *s, float vel);
void ag_sand_pour_trigger(AgSand *s, float intensity);

/* ---------- Wood / Log ---------- */
#define AG_WOOD_PARTIALS 6

typedef struct AgWood {
    double sr;
    float gain;
    float wood_tone; /* 0=soft log, 1=hard wood */
    AgOsc partials[AG_WOOD_PARTIALS];
    AgBiquad filters[AG_WOOD_PARTIALS];
    float amps[AG_WOOD_PARTIALS];
    float decays[AG_WOOD_PARTIALS];
    float envs[AG_WOOD_PARTIALS];
    AgBiquad body_lp;
    AgBiquad body_hp;
    AgBiquad crack_hp;
    AgNoise crack_noise;
    AgRng rng;
    AgDCBlock dc;
    int active;
    double t;
    float vel;
    /* creak */
    AgOsc creak_osc;
    AgOsc creak_lfo;
    AgBiquad creak_filter;
    AgEnv creak_env;
    int creak_active;
} AgWood;

void ag_wood_init(AgWood *w, double sr);
void ag_wood_hit(AgWood *w, float freq, float vel, float hardness); /* hardness 0..1 */
float ag_wood_next(AgWood *w);
int ag_wood_active(const AgWood *w);
void ag_wood_creak_trigger(AgWood *w, float duration, float stress);

/* Log is deeper, more resonant, uses same struct but different preset */
typedef AgWood AgLog;
void ag_log_init(AgLog *l, double sr);
void ag_log_hit(AgLog *l, float freq, float vel);
float ag_log_next(AgLog *l);
void ag_log_creak_trigger(AgLog *l, float duration, float stress);
int ag_log_active(const AgLog *l);

/* ---------- Metal ---------- */
#define AG_METAL_PARTIALS 12

typedef struct AgMetal {
    double sr;
    float gain;
    AgOsc partials[AG_METAL_PARTIALS];
    AgBiquad filters[AG_METAL_PARTIALS];
    float amps[AG_METAL_PARTIALS];
    float decays[AG_METAL_PARTIALS];
    float envs[AG_METAL_PARTIALS];
    AgBiquad body_bp;
    AgBiquad body_hp;
    AgBiquad scrape_bp;
    AgNoise scrape_noise;
    AgOsc scrape_lfo;
    AgRng rng;
    AgDCBlock dc;
    int active;
    double t;
    float vel;
    float metallic; /* 0..1 */
} AgMetal;

void ag_metal_init(AgMetal *m, double sr);
void ag_metal_hit(AgMetal *m, float freq, float vel, float metallic);
float ag_metal_next(AgMetal *m);
int ag_metal_active(const AgMetal *m);
float ag_metal_scrape_next(AgMetal *m, float pressure); /* continuous scrape */
void ag_metal_clang(AgMetal *m, float freq, float vel); /* big clang */

/* ---------- Stone ---------- */
typedef struct AgStone {
    AgWood wood; /* reuse modal but harder */
    AgBiquad hard_hp;
    AgNoise debris_noise;
    AgBiquad debris_bp;
    AgEnv debris_env;
} AgStone;

void ag_stone_init(AgStone *s, double sr);
void ag_stone_hit(AgStone *s, float freq, float vel);
float ag_stone_next(AgStone *s);
int ag_stone_active(const AgStone *s);

/* ---------- Glass ---------- */
#define AG_GLASS_PARTIALS 8

typedef struct AgGlass {
    double sr;
    float gain;
    AgOsc partials[AG_GLASS_PARTIALS];
    AgBiquad filters[AG_GLASS_PARTIALS];
    float amps[AG_GLASS_PARTIALS];
    float decays[AG_GLASS_PARTIALS];
    float envs[AG_GLASS_PARTIALS];
    AgBiquad shimmer_lp;
    AgDCBlock dc;
    AgRng rng;
    int active;
    double t;
} AgGlass;

void ag_glass_init(AgGlass *g, double sr);
void ag_glass_clink(AgGlass *g, float freq, float vel);
void ag_glass_shatter(AgGlass *g, float intensity);
float ag_glass_next(AgGlass *g);
int ag_glass_active(const AgGlass *g);

/* ---------- Shimmer Pro (pitch-shifted reverb tail) ---------- */
#define AG_SHIMMER_PRO_BUF 88200 /* 2 sec at 44.1k */

typedef struct AgShimmerPro {
    double sr;
    float gain;
    float feedback;
    float shift; /* pitch shift factor, 2=octave up */
    float shimmer_mix;
    float damping;
    float *buf;
    int buf_size;
    int write_pos;
    float read_pos;
    AgBiquad lp;
    AgBiquad hp;
    AgBiquad presence;
    AgBiquad input_hp;
    AgDCBlock dc;
    AgReverb reverb;
    AgOsc lfo;
    int owned;
} AgShimmerPro;

void ag_shimmer_pro_init(AgShimmerPro *sh, double sr, float shift);
void ag_shimmer_pro_free(AgShimmerPro *sh);
void ag_shimmer_pro_set(AgShimmerPro *sh, float feedback, float mix, float damping);
float ag_shimmer_pro_process(AgShimmerPro *sh, float in);
void ag_shimmer_pro_process_stereo(AgShimmerPro *sh, float in_l, float in_r, float *out_l, float *out_r);

#ifdef __cplusplus
}
#endif

#endif

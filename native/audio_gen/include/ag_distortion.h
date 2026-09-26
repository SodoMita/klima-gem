#ifndef AG_DISTORTION_H
#define AG_DISTORTION_H

#include "ag_common.h"
#include "ag_filter.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct AgDistortion {
    float drive;
    float mix;
    float tone;
    float sr;
    AgBiquad lp, hp;
    AgDCBlock dc;
} AgDistortion;

void ag_dist_init(AgDistortion *d, float sr);
void ag_dist_set(AgDistortion *d, float drive, float mix, float tone);
float ag_dist_process(AgDistortion *d, float in);

typedef struct AgBitcrush {
    float bit_depth;
    float sample_rate_div;
    float sr;
    float hold;
    float last;
    double timer;
    double hold_time;
    AgBiquad aa_lp;
    AgRng rng;
} AgBitcrush;

void ag_bitcrush_init(AgBitcrush *bc, float sr);
void ag_bitcrush_set(AgBitcrush *bc, float bits, float sr_div);
float ag_bitcrush_process(AgBitcrush *bc, float in);

typedef struct AgWavefolder {
    float threshold;
    float gain;
    float offset;
    float smooth;
} AgWavefolder;

void ag_wavefolder_init(AgWavefolder *wf);
float ag_wavefolder_process(AgWavefolder *wf, float in);

typedef struct AgCompressor {
    float threshold_db;
    float ratio;
    float attack_ms;
    float release_ms;
    float makeup_db;
    float knee_db;
    float sr;
    float env;
    float rms;
    float gain_smooth;
    AgBiquad sidechain_hp;
} AgCompressor;

void ag_comp_init(AgCompressor *c, float sr);
void ag_comp_set(AgCompressor *c, float thresh_db, float ratio, float attack_ms, float release_ms, float makeup_db);
float ag_comp_process(AgCompressor *c, float in);

#ifdef __cplusplus
}
#endif

#endif

#ifndef AG_REVERB_H
#define AG_REVERB_H

#include "ag_common.h"

#ifdef __cplusplus
extern "C" {
#endif

/* High-quality Freeverb-style reverb with modulation and early reflections */

#define AG_REVERB_COMBS 8
#define AG_REVERB_ALLP 4

typedef struct AgComb {
    float *buf;
    int size;
    int pos;
    float feedback;
    float damp;
    float filter_store;
} AgComb;

typedef struct AgAllpass {
    float *buf;
    int size;
    int pos;
    float feedback;
} AgAllpass;

typedef struct AgReverb {
    AgComb combs[AG_REVERB_COMBS];
    AgAllpass allps[AG_REVERB_ALLP];
    float *comb_bufs[AG_REVERB_COMBS];
    float *allp_bufs[AG_REVERB_ALLP];
    float *early_bufs[4];
    int early_sizes[4];
    int early_pos[4];
    int sr;
    float room_size;
    float damping;
    float wet;
    float dry;
    float width;
    float gain;
    float mod_depth;
    float mod_freq;
    float mod_phase;
    float comb_mod_phase[AG_REVERB_COMBS];
    int initialized;
} AgReverb;

void ag_reverb_init(AgReverb *rv, int sr);
void ag_reverb_free(AgReverb *rv);
void ag_reverb_set_room_size(AgReverb *rv, float room_size);
void ag_reverb_set_damping(AgReverb *rv, float damping);
void ag_reverb_set_wet(AgReverb *rv, float wet);
void ag_reverb_set_dry(AgReverb *rv, float dry);
void ag_reverb_set_width(AgReverb *rv, float width);
void ag_reverb_set_gain(AgReverb *rv, float gain);
float ag_reverb_process(AgReverb *rv, float in);
void ag_reverb_process_stereo(AgReverb *rv, float in_l, float in_r, float *out_l, float *out_r);
void ag_reverb_process_block(AgReverb *rv, float *buf, int frames);
void ag_reverb_process_block_stereo(AgReverb *rv, float *interleaved, int frames);

typedef struct AgSchroeder {
    float *comb_bufs[4];
    int comb_sizes[4];
    int comb_pos[4];
    float comb_fb[4];
    float comb_filter[4];
    float *allp_bufs[2];
    int allp_sizes[2];
    int allp_pos[2];
    int sr;
    float wet, dry;
    int initialized;
} AgSchroeder;

void ag_schroeder_init(AgSchroeder *rv, int sr);
void ag_schroeder_free(AgSchroeder *rv);
float ag_schroeder_process(AgSchroeder *rv, float in);

#ifdef __cplusplus
}
#endif

#endif

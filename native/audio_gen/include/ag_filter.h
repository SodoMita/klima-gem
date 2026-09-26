#ifndef AG_FILTER_H
#define AG_FILTER_H

#include "ag_common.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    AG_FILTER_LP = 0,
    AG_FILTER_HP,
    AG_FILTER_BP,
    AG_FILTER_NOTCH,
    AG_FILTER_PEAK,
    AG_FILTER_LOSHELF,
    AG_FILTER_HISHELF,
    AG_FILTER_LP_1POLE,
    AG_FILTER_HP_1POLE,
    AG_FILTER_COUNT
} AgFilterType;

typedef struct AgBiquad {
    float b0,b1,b2,a1,a2;
    float z1,z2;
    double b0_d,b1_d,b2_d,a1_d,a2_d; /* double for coeffs */
    float freq, q, gain_db;
    AgFilterType type;
} AgBiquad;

void ag_biquad_init(AgBiquad *f);
void ag_biquad_set(AgBiquad *f, AgFilterType type, float freq, float q, float gain_db, float sr);
void ag_biquad_set_hq(AgBiquad *f, AgFilterType type, float freq, float q, float gain_db, float sr);
float ag_biquad_process(AgBiquad *f, float in);
float ag_biquad_process_hq(AgBiquad *f, float in);
void ag_biquad_process_block(AgBiquad *f, float *buf, int n);
void ag_biquad_process_block_hq(AgBiquad *f, float *buf, int n);

typedef struct AgOnePole {
    float a0,b1;
    float z1;
    float freq;
} AgOnePole;

void ag_onepole_lp(AgOnePole *f, float freq, float sr);
void ag_onepole_hp(AgOnePole *f, float freq, float sr);
void ag_onepole_lp_hq(AgOnePole *f, float freq, float sr);
float ag_onepole_process(AgOnePole *f, float in);
float ag_onepole_process_hq(AgOnePole *f, float in);

/* SVF with ZDF */
typedef struct AgSVF {
    float freq;
    float q;
    float sr;
    float ic1eq, ic2eq;
    float g, k, a1, a2, a3;
} AgSVF;

void ag_svf_init(AgSVF *svf, float freq, float q, float sr);
void ag_svf_set(AgSVF *svf, float freq, float q);
void ag_svf_set_hq(AgSVF *svf, float freq, float q, float sr);
void ag_svf_process(AgSVF *svf, float in, float *lp, float *hp, float *bp, float *notch);
void ag_svf_process_hq(AgSVF *svf, float in, float *lp, float *hp, float *bp, float *notch, float *peak);

typedef struct AgDCBlock {
    float x1,y1;
    float r;
} AgDCBlock;

void ag_dcblock_init(AgDCBlock *f);
void ag_dcblock_set(AgDCBlock *f, float cutoff, float sr);
float ag_dcblock_process(AgDCBlock *f, float in);

/* Moog ladder ZDF with 4x oversampling */
typedef struct AgLadder {
    float freq;
    float res;
    float sr;
    float stage[4];
    float delay[4];
    float acr, k;
    float oversample_buf[8];
} AgLadder;

void ag_ladder_init(AgLadder *f, float freq, float res, float sr);
void ag_ladder_set(AgLadder *f, float freq, float res);
void ag_ladder_set_hq(AgLadder *f, float freq, float res, float sr);
float ag_ladder_process(AgLadder *f, float in);
float ag_ladder_process_hq(AgLadder *f, float in);
float ag_ladder_process_oversampled(AgLadder *f, float in);

/* 2-pole cascade for steeper slope */
typedef struct AgFilterCascade {
    AgBiquad bq[4];
    int stages;
} AgFilterCascade;

void ag_cascade_init(AgFilterCascade *c);
void ag_cascade_set_lp(AgFilterCascade *c, float freq, float q, float sr, int stages);
float ag_cascade_process(AgFilterCascade *c, float in);

#ifdef __cplusplus
}
#endif

#endif

#ifndef AG_OSC_H
#define AG_OSC_H

#include "ag_common.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    AG_OSC_SINE = 0,
    AG_OSC_SAW,
    AG_OSC_SQUARE,
    AG_OSC_TRI,
    AG_OSC_NOISE,
    AG_OSC_PULSE,
    AG_OSC_SAW_TRI,
    AG_OSC_SAW2,      /* double saw detuned */
    AG_OSC_SUPERSAW,  /* 7 detuned saws */
    AG_OSC_COUNT
} AgOscType;

typedef struct AgOsc {
    double phase;
    double freq;
    double sr;
    int type;
    double pw;
    double detune;
    AgRng rng;
    double last_out;
    /* HQ state */
    double phase2;      /* second phase for double saw */
    float last_blep;
    float tri_state;    /* for DPW triangle */
    float tri_last;
    double sync_phase;
    float dc_block_x1, dc_block_y1;
} AgOsc;

void ag_osc_init(AgOsc *osc, AgOscType type, double sr);
void ag_osc_set_freq(AgOsc *osc, double freq);
void ag_osc_set_type(AgOsc *osc, AgOscType type);
void ag_osc_set_pw(AgOsc *osc, double pw);
void ag_osc_reset(AgOsc *osc);
void ag_osc_set_detune(AgOsc *osc, double cents);

float ag_osc_next_raw(AgOsc *osc);
float ag_osc_next(AgOsc *osc);
float ag_osc_next_hq(AgOsc *osc); /* oversampled HQ */

float ag_osc_sine_f(float phase01);
float ag_osc_saw_f(float phase01);
float ag_osc_square_f(float phase01, float pw);
float ag_osc_tri_f(float phase01);

/* Improved BLEPs */
float ag_poly_blep(float t, float dt);
float ag_poly_blep_4(float t, float dt); /* 4th order */
float ag_poly_blamp(float t, float dt); /* for triangle */

#define AG_WT_SIZE 1024
#define AG_WT_SIZE_MASK (AG_WT_SIZE-1)
typedef struct AgWavetable {
    float table[AG_WT_SIZE];
    float table_hf[AG_WT_SIZE]; /* high freq mip */
} AgWavetable;

void ag_wt_sine(AgWavetable *wt);
void ag_wt_saw(AgWavetable *wt);
void ag_wt_square(AgWavetable *wt, float pw);
void ag_wt_tri(AgWavetable *wt);
void ag_wt_morph(AgWavetable *out, const AgWavetable *a, const AgWavetable *b, float mix);
void ag_wt_bandlimit(AgWavetable *wt, double sr, double max_freq);

typedef struct AgWTOsc {
    AgWavetable wt;
    double phase;
    double freq;
    double sr;
    float interp; /* 0=linear 1=cubic */
} AgWTOsc;

void ag_wt_osc_init(AgWTOsc *osc, const AgWavetable *wt, double sr);
float ag_wt_osc_next(AgWTOsc *osc);
float ag_wt_osc_next_cubic(AgWTOsc *osc);

typedef struct AgLFO {
    AgOsc osc;
    float depth;
    float offset;
    float smooth; /* smoothing */
    float last;
} AgLFO;

void ag_lfo_init(AgLFO *lfo, AgOscType type, double freq, double sr, float depth);
float ag_lfo_next(AgLFO *lfo);
float ag_lfo_next_smooth(AgLFO *lfo);

#ifdef __cplusplus
}
#endif

#endif

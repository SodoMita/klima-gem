#ifndef AG_FM_H
#define AG_FM_H

#include "ag_common.h"
#include "ag_osc.h"
#include "ag_envelope.h"
#include "ag_filter.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct AgFmOp {
    AgOsc osc;
    AgEnv env;
    float level;
    float freq_mul;
    float detune;
    float feedback;
    float last_out;
} AgFmOp;

typedef struct AgFmVoice2 {
    AgFmOp mod;
    AgFmOp car;
    float mod_index;
    float feedback;
    float gain;
    double sr;
    int active;
    float last_mod;
    int oversample;
    AgDCBlock dc_block;
} AgFmVoice2;

void ag_fm_op_init(AgFmOp *op, double sr, float freq_mul, float level);
void ag_fm_voice2_init(AgFmVoice2 *v, double sr, float base_freq, float mod_index);
void ag_fm_voice2_note_on(AgFmVoice2 *v, float freq, float vel);
void ag_fm_voice2_note_off(AgFmVoice2 *v);
int ag_fm_voice2_active(const AgFmVoice2 *v);
float ag_fm_voice2_next(AgFmVoice2 *v);

typedef enum {
    AG_FM_ALG_4_STACK = 0,
    AG_FM_ALG_3_PLUS_1,
    AG_FM_ALG_2x2,
    AG_FM_ALG_1_PLUS_3,
    AG_FM_ALG_COUNT
} AgFmAlg4;

typedef struct AgFmVoice4 {
    AgFmOp ops[4];
    AgFmAlg4 alg;
    float gain;
    double sr;
    int active;
    float fb_state;
    int oversample;
    AgDCBlock dc_block;
} AgFmVoice4;

void ag_fm_voice4_init(AgFmVoice4 *v, double sr, AgFmAlg4 alg);
void ag_fm_voice4_note_on(AgFmVoice4 *v, float freq, float vel);
void ag_fm_voice4_note_off(AgFmVoice4 *v);
int ag_fm_voice4_active(const AgFmVoice4 *v);
float ag_fm_voice4_next(AgFmVoice4 *v);

typedef enum {
    AG_FM_PRESET_BASS = 0,
    AG_FM_PRESET_LEAD,
    AG_FM_PRESET_PAD,
    AG_FM_PRESET_BELL,
    AG_FM_PRESET_EPIANO,
    AG_FM_PRESET_BRASS,
    AG_FM_PRESET_COUNT
} AgFmPreset;

void ag_fm_apply_preset_2op(AgFmVoice2 *v, AgFmPreset preset);
void ag_fm_apply_preset_4op(AgFmVoice4 *v, AgFmPreset preset);

#ifdef __cplusplus
}
#endif

#endif

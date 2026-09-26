#ifndef AG_CHIPTUNE_H
#define AG_CHIPTUNE_H

#include "ag_common.h"
#include "ag_osc.h"
#include "ag_envelope.h"

#ifdef __cplusplus
extern "C" {
#endif

/* NES-style 2A03 chip emulation-ish, simplified but authentic sounding */

typedef enum {
    AG_CHIP_SQUARE = 0,
    AG_CHIP_TRI,
    AG_CHIP_NOISE,
    AG_CHIP_DPCM /* not implemented, placeholder */
} AgChipType;

typedef struct AgChipSquare {
    double phase;
    double freq;
    double sr;
    int duty; /* 0..3 = 12.5%,25%,50%,75% */
    float volume; /* 0..1 */
    AgEnv env;
    float env_level;
    int active;
    double sweep_t;
} AgChipSquare;

typedef struct AgChipTri {
    double phase;
    double freq;
    double sr;
    float volume;
    int active;
    int linear_counter;
} AgChipTri;

typedef struct AgChipNoise {
    uint16_t lfsr; /* 15-bit LFSR */
    double freq;
    double sr;
    double timer;
    int mode; /* 0=long, 1=short */
    float volume;
    AgEnv env;
    int active;
} AgChipNoise;

void ag_chip_square_init(AgChipSquare *sq, double sr);
void ag_chip_square_note_on(AgChipSquare *sq, float freq, float vol, int duty);
void ag_chip_square_note_off(AgChipSquare *sq);
float ag_chip_square_next(AgChipSquare *sq);

void ag_chip_tri_init(AgChipTri *tri, double sr);
void ag_chip_tri_note_on(AgChipTri *tri, float freq, float vol);
void ag_chip_tri_note_off(AgChipTri *tri);
float ag_chip_tri_next(AgChipTri *tri);

void ag_chip_noise_init(AgChipNoise *ns, double sr);
void ag_chip_noise_note_on(AgChipNoise *ns, float freq, float vol, int short_mode);
void ag_chip_noise_note_off(AgChipNoise *ns);
float ag_chip_noise_next(AgChipNoise *ns);

/* Full chip with 2 squares + tri + noise */
typedef struct AgChip {
    AgChipSquare sq1, sq2;
    AgChipTri tri;
    AgChipNoise noise;
    double sr;
    float master_gain;
} AgChip;

void ag_chip_init(AgChip *chip, double sr);
void ag_chip_set_gain(AgChip *chip, float gain);
float ag_chip_next(AgChip *chip); /* mono mix */

/* Arpeggiator for chiptune leads */
typedef struct AgArp {
    int notes[8];
    int count;
    int pos;
    double timer;
    double step_dur;
    double sr;
    int active;
} AgArp;

void ag_arp_init(AgArp *arp, double sr, double step_dur);
void ag_arp_set_notes(AgArp *arp, const int *midi_notes, int count);
void ag_arp_trigger(AgArp *arp);
int ag_arp_next_midi(AgArp *arp);

/* Chiptune sequencer - pattern based */
#define AG_CHIP_PATTERN_LEN 16
typedef struct AgChipPattern {
    int sq1_midi[AG_CHIP_PATTERN_LEN];
    int sq2_midi[AG_CHIP_PATTERN_LEN];
    int tri_midi[AG_CHIP_PATTERN_LEN];
    int noise_on[AG_CHIP_PATTERN_LEN];
    int sq1_duty[AG_CHIP_PATTERN_LEN];
    int sq2_duty[AG_CHIP_PATTERN_LEN];
} AgChipPattern;

void ag_chip_pattern_init(AgChipPattern *pat);
void ag_chip_pattern_set(AgChipPattern *pat, int step, int sq1, int sq2, int tri, int noise);

typedef struct AgChipSequencer {
    AgChip chip;
    AgChipPattern pattern;
    double bpm;
    double sr;
    double playhead;
    double step_dur;
    int step;
} AgChipSequencer;

void ag_chip_seq_init(AgChipSequencer *seq, double sr, double bpm);
void ag_chip_seq_set_pattern(AgChipSequencer *seq, const AgChipPattern *pat);
float ag_chip_seq_next(AgChipSequencer *seq);

#ifdef __cplusplus
}
#endif

#endif

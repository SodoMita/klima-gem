#ifndef AG_SEQUENCER_H
#define AG_SEQUENCER_H

#include "ag_common.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Generic step sequencer + arpeggiator + euclidean */

#define AG_SEQ_MAX_STEPS 64
#define AG_SEQ_MAX_TRACKS 8

typedef struct AgStep {
    int midi;      /* -1 = rest */
    float vel;     /* 0..1 */
    float gate;    /* 0..1 portion of step duration */
    float prob;    /* 0..1 probability */
} AgStep;

typedef struct AgTrack {
    AgStep steps[AG_SEQ_MAX_STEPS];
    int length;
    int root_midi;
    AgScale scale;
    int use_scale; /* if true, midi is degree */
} AgTrack;

typedef struct AgSequencer {
    AgTrack tracks[AG_SEQ_MAX_TRACKS];
    int track_count;
    int steps; /* global steps per bar, e.g. 16 */
    float bpm;
    double sr;
    double playhead;
    double step_dur;
    int current_step;
    AgRng rng;
    float swing;
    int playing;
} AgSequencer;

void ag_seq_init(AgSequencer *seq, double sr, float bpm, int steps_per_bar);
void ag_seq_set_bpm(AgSequencer *seq, float bpm);
void ag_seq_set_swing(AgSequencer *seq, float swing);
void ag_seq_clear_track(AgSequencer *seq, int track);
void ag_seq_set_step(AgSequencer *seq, int track, int step_idx, int midi, float vel, float gate);
void ag_seq_set_scale(AgSequencer *seq, int track, const AgScale *scale, int root_midi);
int ag_seq_tick(AgSequencer *seq); /* returns 1 if new step started */
int ag_seq_current_step(const AgSequencer *seq);
void ag_seq_get_active_notes(const AgSequencer *seq, int *out_midi, float *out_vel, int *out_count, int max_notes);

/* Euclidean rhythm generator */
void ag_euclidean(int *out_steps, int len, int pulses, int rotation);
void ag_seq_fill_euclidean(AgSequencer *seq, int track, int len, int pulses, int rotation, int midi, float vel);

/* Arpeggiator */
typedef enum {
    AG_ARP_UP = 0,
    AG_ARP_DOWN,
    AG_ARP_UP_DOWN,
    AG_ARP_RANDOM,
    AG_ARP_CONVERGE,
    AG_ARP_COUNT
} AgArpMode;

typedef struct AgArpeggiator {
    int held_notes[16];
    int held_count;
    int pos;
    int dir; /* for up-down */
    AgArpMode mode;
    double timer;
    double step_dur;
    double sr;
    AgRng rng;
    int octave_range;
    int current_midi;
    int active;
} AgArpeggiator;

void ag_arpeggiator_init(AgArpeggiator *arp, double sr, float rate_hz);
void ag_arpeggiator_set_mode(AgArpeggiator *arp, AgArpMode mode);
void ag_arpeggiator_note_on(AgArpeggiator *arp, int midi);
void ag_arpeggiator_note_off(AgArpeggiator *arp, int midi);
int ag_arpeggiator_next(AgArpeggiator *arp); /* returns midi or -1 if no tick */
int ag_arpeggiator_current(const AgArpeggiator *arp);

/* Chord generator */
typedef enum {
    AG_CHORD_MAJOR = 0,
    AG_CHORD_MINOR,
    AG_CHORD_DIM,
    AG_CHORD_AUG,
    AG_CHORD_SUS2,
    AG_CHORD_SUS4,
    AG_CHORD_MAJ7,
    AG_CHORD_MIN7,
    AG_CHORD_DOM7,
    AG_CHORD_COUNT
} AgChordType;

void ag_chord_make(AgChord *out, AgChordType type, int inversion);
int ag_chord_to_midi(const AgChord *chord, int root_midi, int *out_midi, int max_notes);

#ifdef __cplusplus
}
#endif

#endif

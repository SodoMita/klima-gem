#ifndef SCENE_SCORE_MIX_H
#define SCENE_SCORE_MIX_H

#include <stdint.h>

/* Live score mixer. Samples are generated as they are requested. Nothing is
 * baked into a loop: a new score crossfades, an adjustment changes future
 * bars, and reseed only affects notes that have not been scheduled yet.
 */

#define SCENE_SCORE_RATE 48000
#define SCENE_SCORE_VOICES 48
#define SCENE_SCORE_LAYERS 2
#define SCENE_SCORE_QUEUE 128
#define SCENE_SCORE_SCALE_MAX 8
#define SCENE_SCORE_CHORD_MAX 8
#define SCENE_SCORE_TONE_MAX 4
#define SCENE_SCORE_PARAMS 60

enum {
	SCORE_BPM = 0,
	SCORE_ROOT = 1,
	SCORE_SHAPE = 2,
	SCORE_PAD = 3,
	SCORE_PLUCK = 4,
	SCORE_BASS = 5,
	SCORE_PLUCKS = 6,
	SCORE_BASS_HITS = 7,
	SCORE_PLUCK_SHIFT = 8,
	SCORE_BASS_SHIFT = 9,
	SCORE_SCALE_N = 10,
	SCORE_SCALE = 11,
	SCORE_CHORD_N = 19,
	SCORE_CHORDS = 20
};

typedef struct ScoreSpec {
	double bpm;
	int root;
	double shape;
	double pad;
	double pluck;
	double bass;
	int plucks;
	int bass_hits;
	int pluck_shift;
	int bass_shift;
	int scale_n;
	int scale[SCENE_SCORE_SCALE_MAX];
	int chord_n;
	int chord_size[SCENE_SCORE_CHORD_MAX];
	int chord[SCENE_SCORE_CHORD_MAX][SCENE_SCORE_TONE_MAX];
	uint64_t id;
	uint64_t seed;
} ScoreSpec;

typedef struct Voice {
	double px, py, dx, dy;
	double t, dur, atk, rel, peak, tau, gl, gr;
	int kind;
} Voice;

typedef struct Event {
	double t;
	int midi;
	int kind;
	double dur;
	double peak;
	double pan;
} Event;

typedef struct Layer {
	int active;
	int retiring;
	ScoreSpec spec;
	uint64_t rng;
	double playhead;
	double next_bar;
	double bar_len;
	int bar_index;
	Event queue[SCENE_SCORE_QUEUE];
	int queue_n;
	Voice voices[SCENE_SCORE_VOICES];
	int voice_n;
	double gain;
	double gain_target;
	double gain_step;
	int notes;
} Layer;

typedef struct Mixer {
	Layer layers[SCENE_SCORE_LAYERS];
	int primary;
	double master;
	double master_target;
	double master_step;
	int notes_scheduled;
} Mixer;

void mixer_init(Mixer *mixer);
int score_from_params(ScoreSpec *spec, const double *params, int count, uint64_t id, uint64_t seed);
void mixer_transition(Mixer *mixer, const ScoreSpec *spec, double fade_sec);
void mixer_adjust(Mixer *mixer, const ScoreSpec *spec);
void mixer_reseed(Mixer *mixer, uint64_t seed);
void mixer_release(Mixer *mixer, double fade_sec);
void mixer_set_gain(Mixer *mixer, double gain, double fade_sec);
void mixer_render(Mixer *mixer, float *interleaved, int frames);
int mixer_active(const Mixer *mixer);

#endif

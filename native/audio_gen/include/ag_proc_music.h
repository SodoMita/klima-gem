#ifndef AG_PROC_MUSIC_H
#define AG_PROC_MUSIC_H

#include "ag_common.h"
#include "ag_osc.h"
#include "ag_filter.h"
#include "ag_sequencer.h"
#include "ag_drums.h"
#include "ag_fm.h"
#include "ag_chiptune.h"
#include "ag_ambient.h"
#include "ag_music_box.h"
#include "ag_reverb.h"
#include "ag_delay.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    AG_MOOD_CALM = 0,
    AG_MOOD_WARM,
    AG_MOOD_TENSE,
    AG_MOOD_NIGHT,
    AG_MOOD_DREAM,
    AG_MOOD_LOFI,
    AG_MOOD_CHIPTUNE,
    AG_MOOD_AMBIENT,
    AG_MOOD_RIFT,
    AG_MOOD_FESTIVAL,
    AG_MOOD_LAB,
    AG_MOOD_COUNT
} AgMood;

typedef struct AgProcSpec {
    AgMood mood;
    float bpm;
    int root_midi;
    AgScale scale;
    AgChord progression[8];
    int prog_len;
    float pad_gain;
    float pluck_gain;
    float bass_gain;
    float drums_gain;
    int plucks_per_bar;
    int bass_hits_per_bar;
    int pluck_shift;
    int bass_shift;
    int shape;
    float humanize; /* 0..1 */
    float swing;    /* 0..1 */
    float width;    /* stereo width */
    uint64_t seed;
    uint64_t id;
} AgProcSpec;

#define AG_PROC_MAX_VOICES 64
#define AG_PROC_QUEUE 256

typedef struct AgProcEvent {
    double time;
    int midi;
    int kind;
    float vel;
    float pan;
    float dur;
} AgProcEvent;

typedef struct AgProcVoice {
    AgOsc osc, osc2, osc3;
    AgEnv env;
    AgBiquad filter, filter2;
    AgDCBlock dc;
    double t;
    double dur;
    float peak;
    float pan;
    float gl, gr;
    int kind;
    int active;
    double age;
} AgProcVoice;

typedef struct AgProcMusic {
    AgProcSpec spec;
    AgRng rng;
    double playhead;
    double next_bar;
    double bar_len;
    int bar_index;
    AgProcEvent queue[AG_PROC_QUEUE];
    int queue_n;
    AgProcVoice voices[AG_PROC_MAX_VOICES];
    int voice_n;
    float gain;
    float gain_target;
    float gain_step;
    double sr;
    int notes_scheduled;
    AgReverb reverb;
    AgDelay delay;
    int use_reverb;
    int use_delay;
    AgDrumMachine drums;
    int has_drums;
    AgBiquad master_lp;
    AgDCBlock master_dc;
} AgProcMusic;

void ag_proc_spec_default(AgProcSpec *spec, AgMood mood, uint64_t seed);
void ag_proc_spec_from_mood(AgProcSpec *spec, AgMood mood, int root_midi, float bpm, uint64_t seed);

void ag_proc_init(AgProcMusic *pm, const AgProcSpec *spec, double sr);
void ag_proc_set_spec(AgProcMusic *pm, const AgProcSpec *spec, float fade_sec);
void ag_proc_set_gain(AgProcMusic *pm, float gain, float fade_sec);
void ag_proc_render(AgProcMusic *pm, float *interleaved_stereo, int frames);
int ag_proc_active(const AgProcMusic *pm);

#define AG_PROC_LAYERS 2

typedef struct AgProcMixer {
    AgProcMusic layers[AG_PROC_LAYERS];
    int primary;
    float master;
    float master_target;
    float master_step;
    double sr;
    int notes_scheduled;
    AgBiquad master_lp;
    AgDCBlock master_dc;
} AgProcMixer;

void ag_proc_mixer_init(AgProcMixer *mix, double sr);
void ag_proc_mixer_transition(AgProcMixer *mix, const AgProcSpec *spec, float fade_sec);
void ag_proc_mixer_adjust(AgProcMixer *mix, const AgProcSpec *spec);
void ag_proc_mixer_reseed(AgProcMixer *mix, uint64_t seed);
void ag_proc_mixer_set_gain(AgProcMixer *mix, float gain, float fade_sec);
void ag_proc_mixer_render(AgProcMixer *mix, float *interleaved, int frames);
int ag_proc_mixer_active(const AgProcMixer *mix);

AgMood ag_mood_from_string(const char *str);
const char* ag_mood_to_string(AgMood mood);

#ifdef __cplusplus
}
#endif

#endif

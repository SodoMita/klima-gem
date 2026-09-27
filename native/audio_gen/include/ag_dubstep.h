#ifndef AG_DUBSTEP_H
#define AG_DUBSTEP_H

/* Dubstep generator.
 *
 * Two halves:
 *   1. AgDubstep  - a live, endless dubstep score (halftime drums, LFO wobble
 *                   bass, growls, risers, drops). Rendered on demand, nothing
 *                   is baked to a loop, so intensity and events can change
 *                   while it plays. This is the "active" stage music; the calm
 *                   moods (festival) are left alone. Supports dynamic switching
 *                   between variants (stage, trial, chill, suspense, groove,
 *                   victory, defeat) and picking the best mode for the game state.
 *   2. ag_dub_sfx - deterministic one-shot event sounds cut from the same
 *                   synthesis palette (gem collisions, throws, hits, drops,
 *                   hops/jumps, cannon shots, bell chimes, choir pads).
 *
 * Self-contained DSP (osc + ladder filter + noise) so it also links into the
 * no-libc portable builds.
 */

#include "ag_common.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ---------------------------------------------------------------- one-shots */

typedef enum {
    AG_DUB_SFX_GEM_HIT = 0,   /* gem hits glass/table: clink + sub thump   */
    AG_DUB_SFX_GEM_LAND,      /* gem comes to rest: short woody thud       */
    AG_DUB_SFX_GEM_SPAWN,     /* gem materialises: shimmer up              */
    AG_DUB_SFX_THROW,         /* arm swing: filtered noise whoosh          */
    AG_DUB_SFX_CATCH,         /* caught / snapped into place               */
    AG_DUB_SFX_WOBBLE_BLIP,   /* one wobble cycle, UI accent               */
    AG_DUB_SFX_SUB_DROP,      /* pitch-falling sub boom                    */
    AG_DUB_SFX_IMPACT,        /* the drop: noise slam + sub                */
    AG_DUB_SFX_RISER,         /* build-up                                  */
    AG_DUB_SFX_STAB,          /* short growl stab                          */
    AG_DUB_SFX_CORRECT,       /* challenge passed                          */
    AG_DUB_SFX_WRONG,         /* challenge failed: detuned down-growl      */
    AG_DUB_SFX_WIN,           /* show won: fanfare over a wobble           */
    AG_DUB_SFX_LOSE,          /* show lost                                 */
    AG_DUB_SFX_AIRHORN,       /* the obligatory air horn                   */
    AG_DUB_SFX_SCRATCH,       /* vinyl scratch                             */
    AG_DUB_SFX_REVEAL,        /* word/plaque reveal: chime + sweep         */
    AG_DUB_SFX_TICK,          /* cue tick                                  */
    AG_DUB_SFX_JUMP,          /* Aurora hops/leaps over crossing stone     */
    AG_DUB_SFX_SHOOT,         /* Cannon fires glowing orb at bells         */
    AG_DUB_SFX_BELL_HIT,      /* Orb strikes golden bell: resonant ring    */
    AG_DUB_SFX_PAD_NOTE,      /* Choir pad melodic tone (pitch by energy)  */
    AG_DUB_SFX_PLAQUE_PLACE,  /* Plaque docks in place: lock-in chime      */
    AG_DUB_SFX_COUNT
} AgDubSfxKind;

/* Render a one-shot into a mono buffer.
 * energy 0..1 hardens/retunes the hit (collision speed maps onto it).
 * Returns the number of frames actually written (<= max_frames). */
int ag_dub_sfx_render(int kind, float energy, uint64_t seed,
                      float *out, int max_frames, int sr);

/* Natural length of a one-shot in frames, for buffer sizing. */
int ag_dub_sfx_frames(int kind, int sr);

const char *ag_dub_sfx_name(int kind);

/* ------------------------------------------------------------- live engine */

typedef enum {
    AG_DUB_VARIANT_STAGE = 0,    /* game-show floor: driving, mid wobble      */
    AG_DUB_VARIANT_TRIAL,        /* challenge running: faster, tense          */
    AG_DUB_VARIANT_CHILL,        /* half-speed, filtered, between rounds      */
    AG_DUB_VARIANT_SUSPENSE,     /* 1 gem rolling / tension: heartbeat sub    */
    AG_DUB_VARIANT_GROOVE,       /* both gems placed: heavy peak drop groove  */
    AG_DUB_VARIANT_VICTORY,      /* overall / challenge win: triumphant arps  */
    AG_DUB_VARIANT_DEFEAT,       /* overall / challenge loss: dark sub decay  */
    AG_DUB_VARIANT_COUNT
} AgDubVariant;

typedef enum {
    AG_DUB_EV_RISER = 0,      /* build for two bars then drop              */
    AG_DUB_EV_DROP,           /* impact + full intensity now               */
    AG_DUB_EV_IMPACT,         /* one slam, no section change               */
    AG_DUB_EV_FILL,           /* drum fill on the next bar                 */
    AG_DUB_EV_STAB,           /* single growl stab                         */
    AG_DUB_EV_BREAK,          /* strip to sub + hats for a bar             */
    AG_DUB_EV_COUNT
} AgDubEvent;

#define AG_DUB_STEPS 16
#define AG_DUB_ONESHOTS 6
#define AG_DUB_SHOT_MAX 24000   /* engine one-shots are short by design */
#define AG_DUB_DELAY_MAX 16384

typedef struct AgDubLadder {
    float s1, s2, s3, s4;
    float cut, res, sr;
} AgDubLadder;

typedef struct AgDubOneShot {
    int active;
    int kind;
    float energy;
    uint64_t seed;
    int pos;
    int len;
    float gain;
    float pan;
    float buf[AG_DUB_SHOT_MAX];
} AgDubOneShot;

typedef struct AgDubstep {
    int sr;
    int variant;
    double bpm;
    int root;                 /* midi root of the bassline                 */
    AgRng rng;
    uint64_t seed;

    /* transport */
    double step_len;          /* seconds per 1/16                          */
    double step_timer;
    int step;                 /* 0..15 inside the bar                      */
    int bar;

    /* levels */
    float intensity;
    float intensity_cur;
    float intensity_step;
    float master;
    float master_target;
    float master_step;
    int active;

    /* sections */
    int build_steps;
    int build_total;
    int drop_steps;
    int break_steps;
    int fill_bar;

    /* voices */
    double sub_phase, sub_freq, sub_target;
    float sub_env;
    double wob_p1, wob_p2, wob_p3;
    double wob_freq;
    float wob_env;
    double lfo_phase;
    double lfo_rate;
    float wob_open;
    float growl;
    AgDubLadder ladder;
    float form_z1, form_z2;

    double kick_phase;
    float kick_env, kick_pitch, kick_click;
    float snare_env, snare_tone;
    double snare_phase;
    float hat_env;
    float clap_env;

    float riser_env;
    double riser_phase;
    float riser_pitch;
    float noise_z;

    double stab_phase;
    float stab_env;
    double stab_freq;

    /* pattern */
    int bass_note[AG_DUB_STEPS];
    int bass_gate[AG_DUB_STEPS];
    int wob_div[AG_DUB_STEPS];

    /* fx */
    float dc_x1, dc_y1;
    float hp_z;
    float delay[AG_DUB_DELAY_MAX];
    int delay_w;
    int delay_len;
    float delay_fb;

    AgDubOneShot shots[AG_DUB_ONESHOTS];

    /* introspection */
    int steps_played;
    int hits_kick;
    int hits_snare;
    int events_fired;
} AgDubstep;

void ag_dubstep_init(AgDubstep *d, int sr, int variant, double bpm, uint64_t seed);
void ag_dubstep_set_variant(AgDubstep *d, int variant, double bpm);
void ag_dubstep_set_intensity(AgDubstep *d, float intensity, float fade_sec);
void ag_dubstep_set_gain(AgDubstep *d, float gain, float fade_sec);
void ag_dubstep_event(AgDubstep *d, int event);
/* Switch to best variant & intensity smoothly */
void ag_dubstep_switch_mode(AgDubstep *d, int variant, float intensity, float fade_sec);
/* Fire a one-shot through the music engine (same mix + limiter). */
void ag_dubstep_trigger_sfx(AgDubstep *d, int kind, float energy, float pan, float gain);
void ag_dubstep_release(AgDubstep *d, float fade_sec);
int  ag_dubstep_active(const AgDubstep *d);
/* Interleaved stereo. */
void ag_dubstep_render(AgDubstep *d, float *out, int frames);

#ifdef __cplusplus
}
#endif

#endif

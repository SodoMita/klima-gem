#ifndef AG_NATURE_H
#define AG_NATURE_H

#include "ag_common.h"
#include "ag_osc.h"
#include "ag_filter.h"
#include "ag_noise.h"
#include "ag_envelope.h"

#ifdef __cplusplus
extern "C" {
#endif

/* High-quality nature - physical modeling + formants */

/* Bird: FM chirp with 2 syllables, formant, vibrato, species patterns */
typedef struct AgBird {
    AgOsc osc;            /* carrier */
    AgOsc mod;            /* FM modulator */
    AgOsc vib_lfo;        /* vibrato */
    AgOsc sweep_lfo;      /* frequency sweep control */
    AgEnv env;
    AgEnv env2;           /* second syllable */
    AgBiquad filter;      /* main BP */
    AgBiquad formant;     /* formant */
    AgBiquad hp;          /* air */
    AgRng rng;
    double sr;
    double timer;
    double next_call;
    float gain;
    int active;
    int species;
    float base_freq;
    float sweep_start;
    float sweep_end;
    float sweep_time;
    float syllable_gap;
    int syllable;
    float chirp_rate;
} AgBird;

void ag_bird_init(AgBird *b, double sr, int species);
void ag_bird_trigger(AgBird *b);
float ag_bird_next(AgBird *b);
void ag_bird_next_stereo(AgBird *b, float *l, float *r);
void ag_bird_auto(AgBird *b, float density);

/* Cricket: carrier + AM + pulse train + 2 carriers for beating */
typedef struct AgCricket {
    AgOsc osc1, osc2;
    AgOsc am_lfo;
    AgOsc pulse_lfo;      /* pulse train */
    AgEnv env;
    AgEnv env2;
    AgBiquad bp1, bp2;
    AgRng rng;
    double sr;
    double timer;
    double next_chirp;
    float gain;
    int active;
    float am_depth;
    float chirp_len;
} AgCricket;

void ag_cricket_init(AgCricket *c, double sr);
float ag_cricket_next(AgCricket *c);
void ag_cricket_next_stereo(AgCricket *c, float *l, float *r);
void ag_cricket_auto(AgCricket *c, float density);

/* Cicada: pulse train + BP noise + FM + resonant */
typedef struct AgCicada {
    AgNoise noise;
    AgBiquad bp;          /* main */
    AgBiquad bp2;         /* secondary */
    AgBiquad hp;
    AgOsc am_lfo;         /* 120 Hz */
    AgOsc fm_lfo;         /* FM for buzz */
    AgOsc pulse_osc;      /* pulse */
    AgRng rng;
    double sr;
    double timer;
    float gain;
    float buzz_freq;
} AgCicada;

void ag_cicada_init(AgCicada *c, double sr);
float ag_cicada_next(AgCicada *c);
void ag_cicada_next_stereo(AgCicada *c, float *l, float *r);

/* Frog: dual osc + vocal sac + formant + croak pattern */
typedef struct AgFrog {
    AgOsc osc;            /* fundamental */
    AgOsc osc2;           /* overtone */
    AgOsc sac_lfo;        /* vocal sac resonance mod */
    AgBiquad formant;     /* vocal tract */
    AgBiquad formant2;
    AgBiquad lp;          /* body */
    AgEnv env;
    AgEnv env2;
    AgRng rng;
    double sr;
    double timer;
    double next_croak;
    float gain;
    int active;
    float base_freq;
    int croak_count;
} AgFrog;

void ag_frog_init(AgFrog *f, double sr);
float ag_frog_next(AgFrog *f);
void ag_frog_next_stereo(AgFrog *f, float *l, float *r);
void ag_frog_auto(AgFrog *f, float density);

/* Insect swarm - granular with Hanning envelope */
#define AG_SWARM_MAX 20
typedef struct AgInsectGrain {
    AgOsc osc;
    AgEnv env;
    float pan;
    int active;
    float freq;
    double age;
    double dur;
    float gain;
} AgInsectGrain;

typedef struct AgInsectSwarm {
    AgInsectGrain grains[AG_SWARM_MAX];
    AgRng rng;
    double sr;
    double timer;
    float gain;
    float density;
    float doppler;
    AgOsc swarm_lfo;
} AgInsectSwarm;

void ag_swarm_init(AgInsectSwarm *s, double sr);
float ag_swarm_next(AgInsectSwarm *s);
void ag_swarm_next_stereo(AgInsectSwarm *s, float *l, float *r);

/* Owl: dual tone hoot + formant + second hoot */
typedef struct AgOwl {
    AgOsc osc;            /* fundamental */
    AgOsc osc2;           /* overtone 1.5x */
    AgOsc vib_lfo;
    AgEnv env;
    AgEnv env2;
    AgBiquad filter;      /* LP 800 */
    AgBiquad formant;     /* 600 Hz */
    AgBiquad formant2;    /* 1200 Hz */
    AgRng rng;
    double sr;
    double timer;
    double next_hoot;
    float gain;
    int active;
    int hoot_phase;       /* 0=first hoot, 1=gap, 2=second */
    double hoot_timer;
} AgOwl;

void ag_owl_init(AgOwl *o, double sr);
float ag_owl_next(AgOwl *o);
void ag_owl_next_stereo(AgOwl *o, float *l, float *r);
void ag_owl_auto(AgOwl *o, float density);

#ifdef __cplusplus
}
#endif

#endif

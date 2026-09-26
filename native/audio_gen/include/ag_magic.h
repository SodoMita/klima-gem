#ifndef AG_MAGIC_H
#define AG_MAGIC_H

#include "ag_common.h"
#include "ag_osc.h"
#include "ag_envelope.h"
#include "ag_filter.h"
#include "ag_noise.h"
#include "ag_reverb.h"
#include "ag_delay.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Magic / fantasy procedural SFX: sparkle, chime, spell, enchant, portal, etc.
 * HQ: bandlimited, biquad HQ, shimmer, granular, modal
 */

#define AG_MAGIC_PARTIALS 10
#define AG_MAGIC_SPARKLE_MAX 24
#define AG_MAGIC_SPARKLE_LEN 512

typedef struct AgMagicSparkleGrain {
    float buf[AG_MAGIC_SPARKLE_LEN];
    int pos;
    int len;
    float gain;
    float pan_l, pan_r;
    int active;
    AgBiquad bp;
    double env_phase;
} AgMagicSparkleGrain;

typedef struct AgMagicSparkle {
    double sr;
    float gain;
    float brightness;
    float density;
    AgMagicSparkleGrain grains[AG_MAGIC_SPARKLE_MAX];
    AgRng rng;
    AgBiquad lp;
    AgBiquad hp;
    AgBiquad shimmer_lp;
    AgDCBlock dc;
    double timer;
    double grain_interval;
    AgOsc lfo;
} AgMagicSparkle;

void ag_magic_sparkle_init(AgMagicSparkle *m, double sr);
void ag_magic_sparkle_set(AgMagicSparkle *m, float density, float brightness, float gain);
float ag_magic_sparkle_next(AgMagicSparkle *m);
void ag_magic_sparkle_next_stereo(AgMagicSparkle *m, float *l, float *r);
void ag_magic_sparkle_burst(AgMagicSparkle *m, float intensity);

typedef struct AgMagicChime {
    double sr;
    float gain;
    AgOsc partials[AG_MAGIC_PARTIALS];
    AgBiquad filters[AG_MAGIC_PARTIALS];
    float amps[AG_MAGIC_PARTIALS];
    float decays[AG_MAGIC_PARTIALS];
    float envs[AG_MAGIC_PARTIALS];
    AgBiquad lp;
    AgBiquad hp;
    AgDCBlock dc;
    AgRng rng;
    int active;
    double t;
} AgMagicChime;

void ag_magic_chime_init(AgMagicChime *c, double sr);
void ag_magic_chime_trigger(AgMagicChime *c, float freq, float vel, float magic); /* magic 0..1 = more sparkle */
float ag_magic_chime_next(AgMagicChime *c);
int ag_magic_chime_active(const AgMagicChime *c);

typedef struct AgSpellCast {
    double sr;
    float gain;
    AgOsc osc1, osc2, osc3;
    AgOsc mod;
    AgBiquad bp;
    AgBiquad lp;
    AgBiquad hp;
    AgEnv env;
    AgLFO lfo;
    AgDCBlock dc;
    AgRng rng;
    int active;
    double t;
    float power;
} AgSpellCast;

void ag_spell_cast_init(AgSpellCast *s, double sr);
void ag_spell_cast_trigger(AgSpellCast *s, float base_freq, float power, float duration);
float ag_spell_cast_next(AgSpellCast *s);
int ag_spell_cast_active(const AgSpellCast *s);

typedef struct AgEnchant {
    double sr;
    float gain;
    AgOsc osc1, osc2, osc3;
    AgBiquad filter;
    AgBiquad filter2;
    AgLFO lfo;
    AgLFO lfo2;
    AgMagicSparkle sparkle;
    AgDCBlock dc;
    float intensity;
} AgEnchant;

void ag_enchant_init(AgEnchant *e, double sr, float base_freq);
void ag_enchant_set_intensity(AgEnchant *e, float intensity);
float ag_enchant_next(AgEnchant *e);
void ag_enchant_next_stereo(AgEnchant *e, float *l, float *r);

typedef struct AgPortal {
    double sr;
    float gain;
    AgOsc osc1, osc2, osc3;
    AgBiquad bp1, bp2;
    AgBiquad lp;
    AgBiquad hp;
    AgLFO lfo;
    AgLFO lfo2;
    AgReverb reverb;
    AgDCBlock dc;
    float openness; /* 0 closed ..1 open */
    AgNoise noise;
} AgPortal;

void ag_portal_init(AgPortal *p, double sr, float base_freq);
void ag_portal_set_openness(AgPortal *p, float openness);
float ag_portal_next(AgPortal *p);
void ag_portal_next_stereo(AgPortal *p, float *l, float *r);

typedef struct AgMagicImpact {
    double sr;
    float gain;
    AgMagicChime chime;
    AgSpellCast cast;
    AgMagicSparkle sparkle;
    AgBiquad lp;
    AgDCBlock dc;
    int active;
} AgMagicImpact;

void ag_magic_impact_init(AgMagicImpact *m, double sr);
void ag_magic_impact_trigger(AgMagicImpact *m, float freq, float power);
float ag_magic_impact_next(AgMagicImpact *m);
void ag_magic_impact_next_stereo(AgMagicImpact *m, float *l, float *r);
int ag_magic_impact_active(const AgMagicImpact *m);

#ifdef __cplusplus
}
#endif

#endif

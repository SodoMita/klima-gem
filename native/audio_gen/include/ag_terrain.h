#ifndef AG_TERRAIN_H
#define AG_TERRAIN_H

#include "ag_common.h"
#include "ag_osc.h"
#include "ag_envelope.h"
#include "ag_filter.h"
#include "ag_noise.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Terrain / ground Foley: grass, snow, dirt, gravel, leaves, mud
 * HQ: granular grains, filtered noise, modal impacts, footstep triggers
 */

#define AG_TERRAIN_GRAINS 28
#define AG_TERRAIN_GRAIN_LEN 320

typedef struct AgTerrainGrain {
    float buf[AG_TERRAIN_GRAIN_LEN];
    int pos;
    int len;
    float gain;
    float pan_l, pan_r;
    int active;
    AgBiquad bp;
    AgBiquad hp;
} AgTerrainGrain;

typedef enum {
    AG_TERRAIN_GRASS = 0,
    AG_TERRAIN_SNOW,
    AG_TERRAIN_DIRT,
    AG_TERRAIN_GRAVEL,
    AG_TERRAIN_LEAVES,
    AG_TERRAIN_MUD,
    AG_TERRAIN_COUNT
} AgTerrainType;

typedef struct AgTerrain {
    double sr;
    float gain;
    float density;
    float wetness; /* 0 dry ..1 wet */
    AgTerrainType type;
    AgNoise noise;
    AgNoise noise2;
    AgRng rng;
    AgBiquad lp;
    AgBiquad hp;
    AgBiquad bp_mid;
    AgBiquad presence;
    AgBiquad low_body;
    AgTerrainGrain grains[AG_TERRAIN_GRAINS];
    double timer;
    double grain_interval;
    /* footstep */
    AgEnv foot_env;
    AgEnv foot_env2;
    AgBiquad foot_lp;
    AgBiquad foot_bp;
    AgBiquad foot_hp;
    AgOsc foot_osc;
    int foot_active;
    float foot_gain;
    AgDCBlock dc;
    /* rustle continuous */
    AgOsc rustle_lfo;
    AgOsc rustle_lfo2;
} AgTerrain;

void ag_terrain_init(AgTerrain *t, double sr, AgTerrainType type);
void ag_terrain_set(AgTerrain *t, AgTerrainType type, float density, float wetness, float gain);
float ag_terrain_next(AgTerrain *t);
void ag_terrain_next_stereo(AgTerrain *t, float *l, float *r);
void ag_terrain_footstep_trigger(AgTerrain *t, float vel);
void ag_terrain_rustle_trigger(AgTerrain *t, float intensity);

/* Convenience wrappers */
typedef AgTerrain AgGrass;
typedef AgTerrain AgSnow;
typedef AgTerrain AgDirt;
typedef AgTerrain AgGravel;
typedef AgTerrain AgLeaves;
typedef AgTerrain AgMud;

void ag_grass_init(AgGrass *g, double sr);
float ag_grass_next(AgGrass *g);
void ag_grass_next_stereo(AgGrass *g, float *l, float *r);
void ag_grass_footstep(AgGrass *g, float vel);

void ag_snow_init(AgSnow *s, double sr);
float ag_snow_next(AgSnow *s);
void ag_snow_next_stereo(AgSnow *s, float *l, float *r);
void ag_snow_footstep(AgSnow *s, float vel);
void ag_snow_crunch(AgSnow *s, float intensity);

#ifdef __cplusplus
}
#endif

#endif

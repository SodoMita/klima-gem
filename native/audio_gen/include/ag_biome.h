#ifndef AG_BIOME_H
#define AG_BIOME_H

#include "ag_common.h"
#include "ag_water.h"
#include "ag_fire.h"
#include "ag_nature.h"
#include "ag_weather.h"
#include "ag_ambient.h"
#include "ag_3d.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    AG_BIOME_FOREST = 0,
    AG_BIOME_CAVE,
    AG_BIOME_DESERT,
    AG_BIOME_OCEAN,
    AG_BIOME_CITY,
    AG_BIOME_MOUNTAIN,
    AG_BIOME_JUNGLE,
    AG_BIOME_SWAMP,
    AG_BIOME_TUNDRA,
    AG_BIOME_GRASSLAND,
    AG_BIOME_RIVER,
    AG_BIOME_BEACH,
    AG_BIOME_NEXUS, /* Chrono Nexus specific */
    AG_BIOME_RIFT,
    AG_BIOME_LAB,
    AG_BIOME_COUNT
} AgBiomeType;

typedef struct AgBiomeParams {
    AgBiomeType type;
    float wind;       /* 0..1 */
    float water;      /* 0..1 */
    float birds;      /* 0..1 */
    float insects;    /* 0..1 */
    float fire;       /* 0..1 */
    float weather;    /* 0..1 weather intensity */
    AgWeatherType weather_type;
    float time_of_day; /* 0..1, 0=midnight, 0.5=noon */
    float humidity;   /* 0..1 */
    uint64_t seed;
} AgBiomeParams;

typedef struct AgBiome {
    AgBiomeParams params;
    AgWindSystem wind;
    AgOcean ocean;
    AgRiver river;
    AgStream stream;
    AgWaterfall waterfall;
    AgDrip drip;
    AgFire fire;
    AgBird birds[4];
    AgCricket crickets[2];
    AgCicada cicadas[2];
    AgFrog frogs[2];
    AgOwl owls[1];
    AgInsectSwarm swarm;
    AgWeatherMixer weather;
    AgDrone drone;
    AgGranularPad granular;
    AgRng rng;
    double sr;
    float gain;
} AgBiome;

void ag_biome_params_default(AgBiomeParams *p, AgBiomeType type);
void ag_biome_init(AgBiome *biome, const AgBiomeParams *params, double sr);
void ag_biome_set_params(AgBiome *biome, const AgBiomeParams *params);
float ag_biome_next(AgBiome *biome);
void ag_biome_next_stereo(AgBiome *biome, float *l, float *r);
void ag_biome_render(AgBiome *biome, float *stereo_interleaved, int frames);

/* Helper to get biome from string (scene name) */
AgBiomeType ag_biome_from_string(const char *str);
const char* ag_biome_to_string(AgBiomeType type);

#ifdef __cplusplus
}
#endif

#endif

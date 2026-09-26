#ifndef AG_NOISE_H
#define AG_NOISE_H

#include "ag_common.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct AgNoise {
    AgRng rng;
    /* Pink noise - 7 pole Paul Kellet + 2 extra for better low freq */
    float b0,b1,b2,b3,b4,b5,b6,b7,b8;
    float brown;
    float brown2;
    float pink_scale;
    /* Velvet */
    int velvet_counter;
    int velvet_density;
    /* Blue/violet state */
    float blue_last;
    float violet_last;
    float white_last;
} AgNoise;

void ag_noise_init(AgNoise *n, uint64_t seed);
float ag_noise_white(AgNoise *n);
float ag_noise_pink(AgNoise *n);          /* improved 7-pole */
float ag_noise_pink_hq(AgNoise *n);       /* 9-pole extra low */
float ag_noise_brown(AgNoise *n);         /* 2-stage */
float ag_noise_blue(AgNoise *n);          /* +3dB/oct */
float ag_noise_violet(AgNoise *n);        /* +6dB/oct */
float ag_noise_velvet(AgNoise *n, int density);
float ag_noise_velvet_hq(AgNoise *n, int density, float gain_var);
float ag_noise_crackle(AgNoise *n, float density);
float ag_noise_crackle_hq(AgNoise *n, float density, float sharpness);

#ifdef __cplusplus
}
#endif

#endif

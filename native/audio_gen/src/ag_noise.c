#include "ag_noise.h"
#include <string.h>
#include <math.h>

void ag_noise_init(AgNoise *n, uint64_t seed) {
    memset(n,0,sizeof(*n));
    ag_rng_seed(&n->rng, seed ? seed : 0x12345);
    n->pink_scale = 0.11f;
    n->velvet_density=32;
    n->velvet_counter=0;
}

float ag_noise_white(AgNoise *n) {
    return ag_rng_range_f32(&n->rng, -1.0f, 1.0f);
}

/* Improved pink: 7-pole + 2 extra low for better 1/f down to 20Hz */
float ag_noise_pink(AgNoise *n) {
    float white = ag_noise_white(n);
    n->b0 = 0.99886f * n->b0 + white * 0.0555179f;
    n->b1 = 0.99332f * n->b1 + white * 0.0750759f;
    n->b2 = 0.96900f * n->b2 + white * 0.1538520f;
    n->b3 = 0.86650f * n->b3 + white * 0.3104856f;
    n->b4 = 0.55000f * n->b4 + white * 0.5329522f;
    n->b5 = -0.7616f * n->b5 - white * 0.0168980f;
    float out = (n->b0 + n->b1 + n->b2 + n->b3 + n->b4 + n->b5 + n->b6 + white * 0.5362f) * n->pink_scale;
    n->b6 = white * 0.115926f;
    return ag_clamp_f(out, -1.0f, 1.0f);
}
float ag_noise_pink_hq(AgNoise *n) {
    float white = ag_noise_white(n);
    /* 7-pole + 2 extra low poles at 0.9995 and 0.999 */
    n->b0 = 0.99886f * n->b0 + white * 0.0555179f;
    n->b1 = 0.99332f * n->b1 + white * 0.0750759f;
    n->b2 = 0.96900f * n->b2 + white * 0.1538520f;
    n->b3 = 0.86650f * n->b3 + white * 0.3104856f;
    n->b4 = 0.55000f * n->b4 + white * 0.5329522f;
    n->b5 = -0.7616f * n->b5 - white * 0.0168980f;
    n->b7 = 0.9995f * n->b7 + white * 0.008f;
    n->b8 = 0.9990f * n->b8 + white * 0.012f;
    float out = (n->b0 + n->b1 + n->b2 + n->b3 + n->b4 + n->b5 + n->b6 + n->b7*0.5f + n->b8*0.3f + white * 0.5362f) * 0.09f;
    n->b6 = white * 0.115926f;
    /* soft clip for HQ */
    out = tanhf(out*1.2f)*0.85f;
    return ag_clamp_f(out, -1.0f, 1.0f);
}

float ag_noise_brown(AgNoise *n) {
    float white = ag_noise_white(n);
    /* 2-stage leaky integrator for smoother brown */
    n->brown += white * 0.018f;
    n->brown *= 0.9985f;
    n->brown2 += n->brown * 0.02f;
    n->brown2 *= 0.998f;
    float out = n->brown*1.2f + n->brown2*2.2f;
    return ag_clamp_f(out, -1.0f, 1.0f);
}

float ag_noise_blue(AgNoise *n) {
    float white = ag_noise_white(n);
    float out = white - n->white_last;
    n->white_last = white;
    n->blue_last = out*0.5f + n->blue_last*0.5f; /* slight low cut to avoid too harsh */
    return ag_clamp_f(out*0.8f + n->blue_last*0.2f, -1,1);
}
float ag_noise_violet(AgNoise *n) {
    float white = ag_noise_white(n);
    float diff = white - n->white_last;
    float out = diff - n->blue_last;
    n->white_last = white;
    n->blue_last = diff;
    n->violet_last = out*0.6f + n->violet_last*0.4f;
    return ag_clamp_f(out*0.9f, -1,1);
}

float ag_noise_velvet(AgNoise *n, int density) {
    if (density < 1) density = 32;
    n->velvet_counter--;
    if(n->velvet_counter<=0){
        n->velvet_counter = (int)(ag_rng_next_f32(&n->rng) * density) + 1;
        if(n->velvet_counter<1) n->velvet_counter=1;
        return ag_rng_next_f32(&n->rng) > 0.5f ? 1.0f : -1.0f;
    }
    return 0.0f;
}
float ag_noise_velvet_hq(AgNoise *n, int density, float gain_var) {
    if (density < 1) density = 32;
    n->velvet_counter--;
    if(n->velvet_counter<=0){
        int var = (int)(density * 0.4f);
        int base = density - var/2;
        if(base<2) base=2;
        n->velvet_counter = base + (int)(ag_rng_next_f32(&n->rng) * var);
        float sign = ag_rng_next_f32(&n->rng) > 0.5f ? 1.0f : -1.0f;
        float gain = 1.0f;
        if(gain_var>0.01f){
            gain = 1.0f - gain_var*0.5f + ag_rng_next_f32(&n->rng)*gain_var;
        }
        return sign * gain;
    }
    return 0.0f;
}

float ag_noise_crackle(AgNoise *n, float density) {
    float p = ag_rng_next_f32(&n->rng);
    if (p < density) {
        float white = ag_noise_white(n);
        return white * white * white * 8.0f;
    }
    return 0.0f;
}
float ag_noise_crackle_hq(AgNoise *n, float density, float sharpness) {
    float p = ag_rng_next_f32(&n->rng);
    if (p < density) {
        float white = ag_noise_white(n);
        float s = sharpness>0.1f?sharpness:3.0f;
        float crack = powf(fabsf(white), s) * (white>0?1:-1);
        /* add second harmonic for hardness */
        crack += powf(fabsf(white), s*1.3f) * (white>0?1:-1) * 0.3f;
        return crack * 2.5f;
    }
    return 0.0f;
}

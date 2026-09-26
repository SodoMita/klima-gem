#ifndef AG_COMMON_H
#define AG_COMMON_H

#include <stdint.h>
#include <stddef.h>
#include <math.h>

#ifdef __cplusplus
extern "C" {
#endif

#define AG_PI 3.14159265358979323846
#define AG_TAU 6.28318530717958647692
#define AG_SR_DEFAULT 44100
#define AG_SR_MIN 8000
#define AG_SR_MAX 192000

typedef struct AgRng {
    uint64_t state;
} AgRng;

/* Core RNG - xorshift64* style, deterministic */
static inline void ag_rng_seed(AgRng *rng, uint64_t seed) {
    rng->state = seed ? seed : 0x9E3779B97F4A7C15ULL;
}
static inline uint64_t ag_rng_next_u64(AgRng *rng) {
    uint64_t x = rng->state;
    if (x == 0) x = 0x9E3779B97F4A7C15ULL;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    rng->state = x;
    return x;
}
static inline double ag_rng_next_f64(AgRng *rng) {
    /* 53-bit precision float in [0,1) */
    uint64_t v = ag_rng_next_u64(rng) >> 11;
    return (double)v * (1.0 / 9007199254740992.0);
}
static inline float ag_rng_next_f32(AgRng *rng) {
    return (float)ag_rng_next_f64(rng);
}
static inline double ag_rng_range_f64(AgRng *rng, double lo, double hi) {
    return lo + (hi - lo) * ag_rng_next_f64(rng);
}
static inline float ag_rng_range_f32(AgRng *rng, float lo, float hi) {
    return lo + (hi - lo) * ag_rng_next_f32(rng);
}

/* Math helpers - work without libm if needed, but use libm when available */
static inline double ag_clamp_d(double v, double lo, double hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}
static inline float ag_clamp_f(float v, float lo, float hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}
static inline double ag_lerp_d(double a, double b, double t) {
    return a + (b - a) * t;
}
static inline float ag_lerp_f(float a, float b, float t) {
    return a + (b - a) * t;
}
static inline double ag_midi_to_freq(double midi) {
    return 440.0 * pow(2.0, (midi - 69.0) / 12.0);
}
static inline double ag_freq_to_midi(double freq) {
    if (freq <= 0.0) return 0.0;
    return 69.0 + 12.0 * log2(freq / 440.0);
}
static inline float ag_db_to_lin(float db) {
    return powf(10.0f, db / 20.0f);
}
static inline float ag_lin_to_db(float lin) {
    if (lin <= 0.0000001f) return -120.0f;
    return 20.0f * log10f(lin);
}
static inline double ag_wrap01(double x) {
    x = x - (double)(int64_t)x;
    if (x < 0) x += 1.0;
    return x;
}
static inline float ag_soft_clip(float x) {
    /* tanh-ish soft clip: x / (1+|x|) * 1.4 with saturation control */
    return x / (1.0f + fabsf(x)) * 1.4f;
}
static inline float ag_soft_clip2(float x) {
    /* cubic soft clip */
    if (x > 1.0f) return 1.0f;
    if (x < -1.0f) return -1.0f;
    return x * (1.5f - 0.5f * x * x);
}

/* Buffer helpers */
typedef struct AgBuffer {
    float *data;      /* interleaved */
    int frames;
    int channels;     /* 1 or 2 */
    int sample_rate;
} AgBuffer;

typedef struct AgStereo {
    float l, r;
} AgStereo;

void ag_buffer_clear(AgBuffer *buf);
void ag_buffer_mix_add(AgBuffer *dst, const AgBuffer *src, float gain);
float ag_buffer_rms(const AgBuffer *buf);
float ag_buffer_peak(const AgBuffer *buf);
void ag_buffer_fade_in(AgBuffer *buf, int fade_frames);
void ag_buffer_fade_out(AgBuffer *buf, int fade_frames);
void ag_buffer_pan_stereo(float mono, float pan, float *out_l, float *out_r);

/* Scale / chord helpers */
#define AG_SCALE_MAX 12
#define AG_CHORD_MAX 8
#define AG_CHORD_TONES_MAX 6

typedef struct AgScale {
    int notes[AG_SCALE_MAX];
    int count;
} AgScale;

typedef struct AgChord {
    int tones[AG_CHORD_TONES_MAX];
    int count;
} AgChord;

int ag_scale_degree_to_midi(int degree, int root_midi, const AgScale *scale);
void ag_scale_major(AgScale *out);
void ag_scale_minor(AgScale *out);
void ag_scale_dorian(AgScale *out);
void ag_scale_phrygian(AgScale *out);
void ag_scale_lydian(AgScale *out);
void ag_scale_mixolydian(AgScale *out);
void ag_scale_pentatonic_major(AgScale *out);
void ag_scale_pentatonic_minor(AgScale *out);
void ag_scale_blues(AgScale *out);
void ag_scale_chromatic(AgScale *out);
void ag_scale_octatonic(AgScale *out);
void ag_scale_whole_tone(AgScale *out);

/* Common presets for quick use */
extern const AgScale AG_SCALE_MAJOR;
extern const AgScale AG_SCALE_MINOR;
extern const AgScale AG_SCALE_PENTA_MAJOR;
extern const AgScale AG_SCALE_PENTA_MINOR;

#ifdef __cplusplus
}
#endif

#endif

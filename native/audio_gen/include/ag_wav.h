#ifndef AG_WAV_H
#define AG_WAV_H

#include "ag_common.h"
#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Simple WAV writer - PCM 16-bit or float32 */

int ag_wav_write_f32(const char *path, const float *interleaved, int frames, int channels, int sr);
int ag_wav_write_i16(const char *path, const float *interleaved, int frames, int channels, int sr);
int ag_wav_write_mono_f32(const char *path, const float *mono, int frames, int sr);

/* WAV writer that appends to memory buffer */
typedef struct AgWavMem {
    unsigned char *data;
    size_t size;
    size_t cap;
} AgWavMem;

void ag_wav_mem_init(AgWavMem *wm);
void ag_wav_mem_free(AgWavMem *wm);
int ag_wav_mem_write_f32(AgWavMem *wm, const float *interleaved, int frames, int channels, int sr);

/* Reader - minimal, only PCM 16/24/32 float */
typedef struct AgWavInfo {
    int channels;
    int sample_rate;
    int frames;
    int bits_per_sample;
    int is_float;
} AgWavInfo;

int ag_wav_read_info(const char *path, AgWavInfo *info);
int ag_wav_read_f32(const char *path, float **out_interleaved, AgWavInfo *info); /* caller free */

#ifdef __cplusplus
}
#endif

#endif

#include "ag_wav.h"
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

static void write_u32_le(unsigned char *p, uint32_t v) {
    p[0]=v&0xff; p[1]=(v>>8)&0xff; p[2]=(v>>16)&0xff; p[3]=(v>>24)&0xff;
}
static void write_u16_le(unsigned char *p, uint16_t v) {
    p[0]=v&0xff; p[1]=(v>>8)&0xff;
}
static void write_f32_le(unsigned char *p, float v) {
    uint32_t u; memcpy(&u,&v,sizeof(u));
    write_u32_le(p,u);
}

static int write_wav_header(FILE *f, int frames, int channels, int sr, int bits, int is_float) {
    int byte_rate = sr * channels * bits/8;
    int block_align = channels * bits/8;
    int data_bytes = frames * channels * bits/8;
    int riff_size = 36 + data_bytes;
    unsigned char hdr[44];
    memcpy(hdr,"RIFF",4);
    write_u32_le(hdr+4, riff_size);
    memcpy(hdr+8,"WAVE",4);
    memcpy(hdr+12,"fmt ",4);
    write_u32_le(hdr+16, 16);
    write_u16_le(hdr+20, is_float?3:1);
    write_u16_le(hdr+22, channels);
    write_u32_le(hdr+24, sr);
    write_u32_le(hdr+28, byte_rate);
    write_u16_le(hdr+32, block_align);
    write_u16_le(hdr+34, bits);
    memcpy(hdr+36,"data",4);
    write_u32_le(hdr+40, data_bytes);
    if (fwrite(hdr,1,44,f)!=44) return 0;
    return 1;
}

int ag_wav_write_f32(const char *path, const float *interleaved, int frames, int channels, int sr) {
    FILE *f = fopen(path,"wb");
    if (!f) return 0;
    if (!write_wav_header(f, frames, channels, sr, 32, 1)) { fclose(f); return 0; }
    size_t total = (size_t)frames * channels;
    /* write as little-endian float */
    for (size_t i=0;i<total;i++) {
        unsigned char b[4];
        write_f32_le(b, interleaved[i]);
        if (fwrite(b,1,4,f)!=4) { fclose(f); return 0; }
    }
    fclose(f);
    return 1;
}
int ag_wav_write_i16(const char *path, const float *interleaved, int frames, int channels, int sr) {
    FILE *f = fopen(path,"wb");
    if (!f) return 0;
    if (!write_wav_header(f, frames, channels, sr, 16, 0)) { fclose(f); return 0; }
    size_t total = (size_t)frames * channels;
    for (size_t i=0;i<total;i++) {
        float v = interleaved[i];
        if (v>1.0f) v=1.0f; if (v<-1.0f) v=-1.0f;
        int16_t s = (int16_t)(v*32767.0f);
        unsigned char b[2];
        write_u16_le(b, (uint16_t)s);
        if (fwrite(b,1,2,f)!=2) { fclose(f); return 0; }
    }
    fclose(f);
    return 1;
}
int ag_wav_write_mono_f32(const char *path, const float *mono, int frames, int sr) {
    return ag_wav_write_f32(path, mono, frames, 1, sr);
}

/* Mem writer */
void ag_wav_mem_init(AgWavMem *wm) { memset(wm,0,sizeof(*wm)); }
void ag_wav_mem_free(AgWavMem *wm) { free(wm->data); memset(wm,0,sizeof(*wm)); }
static void mem_ensure(AgWavMem *wm, size_t need) {
    if (wm->cap >= need) return;
    size_t cap = wm->cap ? wm->cap*2 : 1024;
    while (cap < need) cap*=2;
    wm->data = (unsigned char*)realloc(wm->data, cap);
    wm->cap = cap;
}
int ag_wav_mem_write_f32(AgWavMem *wm, const float *interleaved, int frames, int channels, int sr) {
    size_t data_bytes = (size_t)frames * channels * 4;
    size_t total = 44 + data_bytes;
    mem_ensure(wm, total);
    if (!wm->data) return 0;
    unsigned char hdr[44];
    int byte_rate = sr * channels * 4;
    int block_align = channels * 4;
    int riff_size = 36 + (int)data_bytes;
    memcpy(hdr,"RIFF",4);
    write_u32_le(hdr+4, riff_size);
    memcpy(hdr+8,"WAVE",4);
    memcpy(hdr+12,"fmt ",4);
    write_u32_le(hdr+16, 16);
    write_u16_le(hdr+20, 3);
    write_u16_le(hdr+22, channels);
    write_u32_le(hdr+24, sr);
    write_u32_le(hdr+28, byte_rate);
    write_u16_le(hdr+32, block_align);
    write_u16_le(hdr+34, 32);
    memcpy(hdr+36,"data",4);
    write_u32_le(hdr+40, (uint32_t)data_bytes);
    memcpy(wm->data, hdr, 44);
    unsigned char *p = wm->data+44;
    for (size_t i=0;i<(size_t)frames*channels;i++) {
        write_f32_le(p, interleaved[i]);
        p+=4;
    }
    wm->size = total;
    return 1;
}

/* Reader - minimal */
int ag_wav_read_info(const char *path, AgWavInfo *info) {
    FILE *f = fopen(path,"rb");
    if (!f) return 0;
    unsigned char hdr[44];
    if (fread(hdr,1,44,f)!=44) { fclose(f); return 0; }
    if (memcmp(hdr,"RIFF",4)!=0 || memcmp(hdr+8,"WAVE",4)!=0) { fclose(f); return 0; }
    uint16_t audio_fmt = hdr[20] | (hdr[21]<<8);
    uint16_t channels = hdr[22] | (hdr[23]<<8);
    uint32_t sr = hdr[24] | (hdr[25]<<8) | (hdr[26]<<16) | (hdr[27]<<24);
    uint16_t bits = hdr[34] | (hdr[35]<<8);
    uint32_t data_bytes = hdr[40] | (hdr[41]<<8) | (hdr[42]<<16) | (hdr[43]<<24);
    info->channels = channels;
    info->sample_rate = sr;
    info->bits_per_sample = bits;
    info->is_float = (audio_fmt==3);
    info->frames = data_bytes / (channels * bits/8);
    fclose(f);
    return 1;
}
int ag_wav_read_f32(const char *path, float **out_interleaved, AgWavInfo *info) {
    FILE *f = fopen(path,"rb");
    if (!f) return 0;
    unsigned char hdr[44];
    if (fread(hdr,1,44,f)!=44) { fclose(f); return 0; }
    uint16_t audio_fmt = hdr[20] | (hdr[21]<<8);
    uint16_t channels = hdr[22] | (hdr[23]<<8);
    uint32_t sr = hdr[24] | (hdr[25]<<8) | (hdr[26]<<16) | (hdr[27]<<24);
    uint16_t bits = hdr[34] | (hdr[35]<<8);
    uint32_t data_bytes = hdr[40] | (hdr[41]<<8) | (hdr[42]<<16) | (hdr[43]<<24);
    int frames = data_bytes / (channels * bits/8);
    float *data = (float*)malloc((size_t)frames * channels * sizeof(float));
    if (!data) { fclose(f); return 0; }
    if (audio_fmt==3 && bits==32) {
        size_t total = (size_t)frames * channels;
        for (size_t i=0;i<total;i++) {
            unsigned char b[4];
            if (fread(b,1,4,f)!=4) { free(data); fclose(f); return 0; }
            uint32_t u = b[0] | (b[1]<<8) | (b[2]<<16) | (b[3]<<24);
            float v; memcpy(&v,&u,sizeof(v));
            data[i]=v;
        }
    } else if (audio_fmt==1 && bits==16) {
        size_t total = (size_t)frames * channels;
        for (size_t i=0;i<total;i++) {
            unsigned char b[2];
            if (fread(b,1,2,f)!=2) { free(data); fclose(f); return 0; }
            int16_t s = (int16_t)(b[0] | (b[1]<<8));
            data[i]= (float)s / 32768.0f;
        }
    } else {
        free(data); fclose(f); return 0;
    }
    fclose(f);
    if (info) {
        info->channels=channels; info->sample_rate=sr; info->bits_per_sample=bits;
        info->is_float=(audio_fmt==3); info->frames=frames;
    }
    *out_interleaved=data;
    return 1;
}

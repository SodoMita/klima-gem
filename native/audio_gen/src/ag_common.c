#include "ag_common.h"
#include <string.h>
#include <math.h>

const AgScale AG_SCALE_MAJOR = {{0,2,4,5,7,9,11},7};
const AgScale AG_SCALE_MINOR = {{0,2,3,5,7,8,10},7};
const AgScale AG_SCALE_PENTA_MAJOR = {{0,2,4,7,9},5};
const AgScale AG_SCALE_PENTA_MINOR = {{0,3,5,7,10},5};

void ag_buffer_clear(AgBuffer *buf) {
    if (!buf || !buf->data) return;
    memset(buf->data, 0, sizeof(float) * buf->frames * buf->channels);
}
void ag_buffer_mix_add(AgBuffer *dst, const AgBuffer *src, float gain) {
    if (!dst || !src || !dst->data || !src->data) return;
    int n = dst->frames < src->frames ? dst->frames : src->frames;
    int ch = dst->channels < src->channels ? dst->channels : src->channels;
    if (dst->channels == src->channels) {
        for (int i=0;i<n*ch;i++) dst->data[i] += src->data[i]*gain;
    } else if (dst->channels==2 && src->channels==1) {
        for (int i=0;i<n;i++) {
            float s = src->data[i]*gain;
            dst->data[i*2] += s;
            dst->data[i*2+1] += s;
        }
    }
}
float ag_buffer_rms(const AgBuffer *buf) {
    if (!buf || !buf->data || buf->frames==0) return 0.0f;
    double acc=0.0;
    int total = buf->frames * buf->channels;
    for (int i=0;i<total;i++) acc += (double)buf->data[i]*(double)buf->data[i];
    return (float)sqrt(acc / (double)total);
}
float ag_buffer_peak(const AgBuffer *buf) {
    if (!buf || !buf->data) return 0.0f;
    float peak=0.0f;
    int total = buf->frames * buf->channels;
    for (int i=0;i<total;i++) {
        float a = fabsf(buf->data[i]);
        if (a>peak) peak=a;
    }
    return peak;
}
void ag_buffer_fade_in(AgBuffer *buf, int fade_frames) {
    if (!buf || !buf->data) return;
    if (fade_frames > buf->frames) fade_frames = buf->frames;
    for (int i=0;i<fade_frames;i++) {
        float g = (float)i / (float)fade_frames;
        for (int c=0;c<buf->channels;c++) buf->data[i*buf->channels+c] *= g;
    }
}
void ag_buffer_fade_out(AgBuffer *buf, int fade_frames) {
    if (!buf || !buf->data) return;
    if (fade_frames > buf->frames) fade_frames = buf->frames;
    int start = buf->frames - fade_frames;
    for (int i=0;i<fade_frames;i++) {
        float g = 1.0f - (float)i / (float)fade_frames;
        int idx = start + i;
        for (int c=0;c<buf->channels;c++) buf->data[idx*buf->channels+c] *= g;
    }
}
void ag_buffer_pan_stereo(float mono, float pan, float *out_l, float *out_r) {
    /* equal power pan */
    float p = ag_clamp_f(pan, -1.0f, 1.0f);
    float angle = (p * 0.5f + 0.5f) * (float)AG_PI * 0.5f;
    *out_l = mono * cosf(angle);
    *out_r = mono * sinf(angle);
}

int ag_scale_degree_to_midi(int degree, int root_midi, const AgScale *scale) {
    if (!scale || scale->count<=0) return root_midi;
    int n = scale->count;
    int oct, idx;
    if (degree >=0) {
        oct = degree / n;
        idx = degree % n;
    } else {
        int neg = -degree;
        oct = -((neg + n -1)/n);
        idx = degree % n;
        if (idx<0) idx+=n;
    }
    return root_midi + 12*oct + scale->notes[idx];
}

void ag_scale_major(AgScale *out) { out->count=7; int s[7]={0,2,4,5,7,9,11}; memcpy(out->notes,s,sizeof(s)); }
void ag_scale_minor(AgScale *out) { out->count=7; int s[7]={0,2,3,5,7,8,10}; memcpy(out->notes,s,sizeof(s)); }
void ag_scale_dorian(AgScale *out) { out->count=7; int s[7]={0,2,3,5,7,9,10}; memcpy(out->notes,s,sizeof(s)); }
void ag_scale_phrygian(AgScale *out) { out->count=7; int s[7]={0,1,3,5,7,8,10}; memcpy(out->notes,s,sizeof(s)); }
void ag_scale_lydian(AgScale *out) { out->count=7; int s[7]={0,2,4,6,7,9,11}; memcpy(out->notes,s,sizeof(s)); }
void ag_scale_mixolydian(AgScale *out) { out->count=7; int s[7]={0,2,4,5,7,9,10}; memcpy(out->notes,s,sizeof(s)); }
void ag_scale_pentatonic_major(AgScale *out) { out->count=5; int s[5]={0,2,4,7,9}; memcpy(out->notes,s,sizeof(s)); }
void ag_scale_pentatonic_minor(AgScale *out) { out->count=5; int s[5]={0,3,5,7,10}; memcpy(out->notes,s,sizeof(s)); }
void ag_scale_blues(AgScale *out) { out->count=6; int s[6]={0,3,5,6,7,10}; memcpy(out->notes,s,sizeof(s)); }
void ag_scale_chromatic(AgScale *out) { out->count=12; for(int i=0;i<12;i++) out->notes[i]=i; }
void ag_scale_octatonic(AgScale *out) { out->count=8; int s[8]={0,1,3,4,6,7,9,10}; memcpy(out->notes,s,sizeof(s)); }
void ag_scale_whole_tone(AgScale *out) { out->count=6; int s[6]={0,2,4,6,8,10}; memcpy(out->notes,s,sizeof(s)); }

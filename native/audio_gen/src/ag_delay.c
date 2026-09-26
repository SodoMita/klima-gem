#include "ag_delay.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>

void ag_delay_init(AgDelay *d, int sr, float max_delay_ms) {
    memset(d,0,sizeof(*d));
    d->sr = sr>0?sr:AG_SR_DEFAULT;
    d->dry = 0.7f;
    d->wet = 0.3f;
    d->feedback = 0.4f;
    d->delay_ms = 300.0f;
    d->filter_mix = 0.0f;
    if (max_delay_ms < 10) max_delay_ms = 2000.0f;
    int sz = (int)(d->sr * max_delay_ms / 1000.0f) + 4;
    if (sz<8) sz=8;
    d->buf = (float*)calloc(sz, sizeof(float));
    d->size = sz;
    d->pos = 0;
    d->initialized = 1;
    ag_biquad_init(&d->filter);
    ag_biquad_set(&d->filter, AG_FILTER_LP, 6500.0f, 0.7f, 0, (float)sr);
    ag_biquad_init(&d->filter_hp);
    ag_biquad_set(&d->filter_hp, AG_FILTER_HP, 80.0f, 0.7f, 0, (float)sr);
    d->last_out=0;
}
void ag_delay_free(AgDelay *d) {
    if (!d->initialized) return;
    free(d->buf);
    d->initialized=0;
}
void ag_delay_set_delay(AgDelay *d, float delay_ms) {
    float max_ms = (float)(d->size-4) / d->sr * 1000.0f;
    d->delay_ms = ag_clamp_f(delay_ms, 0.1f, max_ms);
}
void ag_delay_set_feedback(AgDelay *d, float fb) { d->feedback = ag_clamp_f(fb, -0.99f, 0.99f); }
void ag_delay_set_wet(AgDelay *d, float wet) { d->wet = ag_clamp_f(wet,0,1); }
void ag_delay_set_dry(AgDelay *d, float dry) { d->dry = ag_clamp_f(dry,0,1); }
void ag_delay_set_filter(AgDelay *d, float cutoff, float q) {
    d->filter_on = 1;
    d->filter_mix=1.0f;
    ag_biquad_set(&d->filter, AG_FILTER_LP, cutoff, q, 0, (float)d->sr);
}
void ag_delay_set_filter_hq(AgDelay *d, float lp_cutoff, float hp_cutoff, float mix) {
    d->filter_on=1;
    d->filter_mix=ag_clamp_f(mix,0,1);
    ag_biquad_set(&d->filter, AG_FILTER_LP, lp_cutoff, 0.7f, 0, (float)d->sr);
    ag_biquad_set(&d->filter_hp, AG_FILTER_HP, hp_cutoff, 0.7f, 0, (float)d->sr);
}
static inline float frac_read(float *buf, int size, float read_pos) {
    int i0 = (int)floorf(read_pos);
    float frac = read_pos - (float)i0;
    i0 = (i0 % size + size) % size;
    int i1 = (i0+1)%size;
    int i2 = (i0+2)%size;
    int i3 = (i0-1+size)%size;
    /* cubic */
    float y0=buf[i3], y1=buf[i0], y2=buf[i1], y3=buf[i2];
    float a0 = y3 - y2 - y0 + y1;
    float a1 = y0 - y1 - a0;
    float a2 = y2 - y0;
    float a3 = y1;
    return a0*frac*frac*frac + a1*frac*frac + a2*frac + a3;
}
float ag_delay_process(AgDelay *d, float in) {
    if (!d->initialized) return in;
    float delay_samples = d->delay_ms * d->sr / 1000.0f;
    if (delay_samples < 0.1f) delay_samples=0.1f;
    if (delay_samples > d->size-4) delay_samples = d->size-4;
    float read_pos = (float)d->pos - delay_samples;
    while(read_pos<0) read_pos+=d->size;
    float delayed = frac_read(d->buf, d->size, read_pos);
    if (d->filter_on){
        float lp = ag_biquad_process(&d->filter, delayed);
        float hp = ag_biquad_process(&d->filter_hp, lp);
        delayed = delayed*(1.0f-d->filter_mix) + hp*d->filter_mix;
    }
    /* saturation in feedback for warmth */
    float fb = delayed * d->feedback;
    fb = tanhf(fb*0.9f)*1.05f;
    /* de-click with soft clip */
    float out = in * d->dry + delayed * d->wet;
    d->buf[d->pos] = in + fb;
    d->pos = (d->pos+1)%d->size;
    d->last_out=out;
    return out;
}
void ag_delay_process_block(AgDelay *d, float *buf, int frames) {
    for (int i=0;i<frames;i++) buf[i]=ag_delay_process(d, buf[i]);
}

/* Ping-pong HQ */
void ag_pingpong_init(AgPingPong *pp, int sr, float max_delay_ms) {
    memset(pp,0,sizeof(*pp));
    ag_delay_init(&pp->left, sr, max_delay_ms);
    ag_delay_init(&pp->right, sr, max_delay_ms);
    pp->cross_feedback = 0.22f;
    pp->width=1.0f;
    ag_biquad_init(&pp->lp);
    ag_biquad_set(&pp->lp, AG_FILTER_LP, 7000,0.7f,0,(float)sr);
}
void ag_pingpong_free(AgPingPong *pp) {
    ag_delay_free(&pp->left);
    ag_delay_free(&pp->right);
}
void ag_pingpong_set_delay(AgPingPong *pp, float delay_ms) {
    ag_delay_set_delay(&pp->left, delay_ms);
    ag_delay_set_delay(&pp->right, delay_ms*1.5f);
}
void ag_pingpong_set_feedback(AgPingPong *pp, float fb) {
    ag_delay_set_feedback(&pp->left, fb);
    ag_delay_set_feedback(&pp->right, fb*0.92f);
}
void ag_pingpong_set_cross(AgPingPong *pp, float cross) { pp->cross_feedback = ag_clamp_f(cross,0,0.9f); }
void ag_pingpong_process(AgPingPong *pp, float in_l, float in_r, float *out_l, float *out_r) {
    float l_in = in_l + in_r * pp->cross_feedback * 0.5f;
    float r_in = in_r + in_l * pp->cross_feedback * 0.5f;
    float l_del = ag_delay_process(&pp->left, l_in);
    float r_del = ag_delay_process(&pp->right, r_in);
    l_del = ag_biquad_process(&pp->lp, l_del);
    r_del = ag_biquad_process(&pp->lp, r_del);
    float width = pp->width;
    float mid = (l_del + r_del)*0.5f;
    float side = (l_del - r_del)*0.5f * width;
    *out_l = mid + side;
    *out_r = mid - side;
}

/* Tape HQ */
void ag_tape_delay_init(AgTapeDelay *td, int sr, float max_delay_ms) {
    memset(td,0,sizeof(*td));
    ag_delay_init(&td->delay, sr, max_delay_ms);
    ag_osc_init(&td->wow_osc, AG_OSC_SINE, sr);
    ag_osc_set_freq(&td->wow_osc, 0.42f);
    ag_osc_init(&td->flutter_osc, AG_OSC_SINE, sr);
    ag_osc_set_freq(&td->flutter_osc, 5.8f);
    ag_osc_init(&td->flutter_osc2, AG_OSC_SINE, sr);
    ag_osc_set_freq(&td->flutter_osc2, 7.3f);
    td->wow_depth = 0.003f;
    td->flutter_depth = 0.0012f;
    td->saturation=0.3f;
    ag_biquad_init(&td->lp);
    ag_biquad_set(&td->lp, AG_FILTER_LP, 8000,0.7f,0,(float)sr);
}
void ag_tape_delay_free(AgTapeDelay *td) { ag_delay_free(&td->delay); }
void ag_tape_delay_set(AgTapeDelay *td, float delay_ms, float fb, float wow, float flutter) {
    ag_delay_set_delay(&td->delay, delay_ms);
    ag_delay_set_feedback(&td->delay, fb*0.92f);
    td->wow_depth = wow;
    td->flutter_depth = flutter;
}
float ag_tape_delay_process(AgTapeDelay *td, float in) {
    float wow = ag_osc_next(&td->wow_osc) * td->wow_depth;
    float flutter = ag_osc_next(&td->flutter_osc) * td->flutter_depth;
    float flutter2 = ag_osc_next(&td->flutter_osc2) * td->flutter_depth*0.5f;
    float mod = 1.0f + wow + flutter + flutter2;
    float orig_delay = td->delay.delay_ms;
    td->delay.delay_ms = orig_delay * mod;
    if(td->delay.delay_ms<0.1f) td->delay.delay_ms=0.1f;
    float out = ag_delay_process(&td->delay, in);
    td->delay.delay_ms = orig_delay;
    /* tape saturation */
    out = tanhf(out*(1.0f+td->saturation*0.5f))* (1.0f/(1.0f+td->saturation*0.3f));
    out = ag_biquad_process(&td->lp, out);
    return out;
}

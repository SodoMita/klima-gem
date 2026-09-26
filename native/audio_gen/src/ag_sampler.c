#include "ag_sampler.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>

void ag_sample_init(AgSample *s) { memset(s,0,sizeof(*s)); }
void ag_sample_alloc(AgSample *s, int frames, int sr) {
    ag_sample_free(s);
    s->data = (float*)calloc(frames, sizeof(float));
    s->frames = frames;
    s->sr = sr;
    s->owned = 1;
}
void ag_sample_free(AgSample *s) {
    if(s->owned && s->data) free(s->data);
    memset(s,0,sizeof(*s));
}
void ag_sample_from_sine(AgSample *s, float freq, float dur, int sr) {
    int frames = (int)(dur * sr);
    ag_sample_alloc(s, frames, sr);
    for(int i=0;i<frames;i++) s->data[i] = sinf(2.0f*(float)AG_PI*freq*i/sr) * 0.5f;
    /* add slight fade in/out to avoid clicks */
    int fade = sr*0.005f;
    if(fade>frames/2) fade=frames/2;
    for(int i=0;i<fade;i++){
        float w = 0.5f - 0.5f*cosf((float)i/fade*(float)AG_PI);
        s->data[i]*=w;
        s->data[frames-1-i]*=w;
    }
}

void ag_sampler_voice_init(AgSamplerVoice *v, AgSample *sample) {
    memset(v,0,sizeof(*v));
    v->sample=sample;
    v->pan_l=0.707f; v->pan_r=0.707f;
    ag_biquad_init(&v->aa_filter);
    ag_dcblock_init(&v->dc);
}
void ag_sampler_voice_play(AgSamplerVoice *v, float pitch_semi, float gain, float pan) {
    v->pos=0;
    v->inc = powf(2.0f, pitch_semi/12.0f);
    /* anti-alias: if pitching up, low-pass */
    if(v->inc>1.0f){
        float cutoff = v->sample ? v->sample->sr / v->inc * 0.45f : 18000;
        if(cutoff>18000) cutoff=18000;
        if(cutoff<200) cutoff=200;
        ag_biquad_set(&v->aa_filter, AG_FILTER_LP, cutoff, 0.7f, 0, v->sample ? v->sample->sr : 44100);
        v->aa_on=1;
    } else {
        v->aa_on=0;
    }
    v->gain=gain;
    ag_buffer_pan_stereo(1.0f, pan, &v->pan_l, &v->pan_r);
    v->active=1;
}
void ag_sampler_voice_stop(AgSamplerVoice *v) { v->active=0; }
int ag_sampler_voice_active(const AgSamplerVoice *v) { return v->active; }

static inline float cubic_interp_sampler(float y0, float y1, float y2, float y3, float mu) {
    float a0 = y3 - y2 - y0 + y1;
    float a1 = y0 - y1 - a0;
    float a2 = y2 - y0;
    float a3 = y1;
    return a0*mu*mu*mu + a1*mu*mu + a2*mu + a3;
}

float ag_sampler_voice_next(AgSamplerVoice *v) {
    if(!v->active || !v->sample || !v->sample->data) return 0.0f;
    double pos = v->pos;
    int idx = (int)floor(pos);
    float frac = (float)(pos - idx);
    if(idx<1 || idx>=v->sample->frames-2) {
        if(v->loop){
            if(pos >= v->sample->frames) v->pos = v->loop_start + fmod(pos - v->sample->frames, v->sample->frames - v->loop_start);
            else if(pos < 0) v->pos = v->loop_start;
            idx = (int)floor(v->pos);
            frac = (float)(v->pos - idx);
            if(idx<1) idx=1;
            if(idx>=v->sample->frames-2) idx=v->sample->frames-3;
        } else {
            if(idx<0 || idx>=v->sample->frames){ v->active=0; return 0.0f; }
        }
    }
    float y0 = v->sample->data[idx-1];
    float y1 = v->sample->data[idx];
    float y2 = v->sample->data[idx+1];
    float y3 = v->sample->data[idx+2];
    float out = cubic_interp_sampler(y0,y1,y2,y3,frac);
    if(v->aa_on) out = ag_biquad_process(&v->aa_filter, out);
    out = ag_dcblock_process(&v->dc, out);
    v->pos += v->inc;
    if(v->pos >= v->sample->frames){
        if(v->loop) v->pos = v->loop_start + fmod(v->pos - v->sample->frames, v->sample->frames - v->loop_start);
        else v->active=0;
    }
    return out * v->gain;
}
void ag_sampler_voice_next_stereo(AgSamplerVoice *v, float *l, float *r) {
    float s = ag_sampler_voice_next(v);
    *l = s * v->pan_l;
    *r = s * v->pan_r;
}

void ag_sampler_inst_init(AgSamplerInstrument *inst) { memset(inst,0,sizeof(*inst)); }
void ag_sampler_inst_add_zone(AgSamplerInstrument *inst, const AgSample *sample, int root_midi, int low_midi, int high_midi) {
    if(inst->zone_count >= AG_SAMPLER_MAX_ZONES) return;
    AgSamplerZone *z = &inst->zones[inst->zone_count++];
    z->sample = *sample;
    z->sample.owned=0;
    z->root_midi=root_midi;
    z->low_midi=low_midi;
    z->high_midi=high_midi;
    z->tune_cents=0;
    z->gain=1.0f;
    z->pan=0.0f;
}
AgSamplerZone* ag_sampler_inst_find_zone(AgSamplerInstrument *inst, int midi) {
    for(int i=0;i<inst->zone_count;i++){
        if(midi >= inst->zones[i].low_midi && midi <= inst->zones[i].high_midi) return &inst->zones[i];
    }
    return inst->zone_count>0 ? &inst->zones[0] : NULL;
}

void ag_sampler_poly_init(AgSamplerPoly *poly, AgSamplerInstrument *inst, double sr) {
    memset(poly,0,sizeof(*poly));
    poly->inst=inst;
    poly->sr=sr>0?sr:AG_SR_DEFAULT;
    poly->voice_count=16;
    if(poly->voice_count>AG_SAMPLER_MAX_VOICES) poly->voice_count=AG_SAMPLER_MAX_VOICES;
    for(int i=0;i<poly->voice_count;i++) ag_sampler_voice_init(&poly->voices[i], NULL);
    poly->gain=1.0f;
}
void ag_sampler_poly_note_on(AgSamplerPoly *poly, int midi, float vel) {
    AgSamplerZone *z = ag_sampler_inst_find_zone(poly->inst, midi);
    if(!z) return;
    AgSamplerVoice *v=NULL;
    for(int i=0;i<poly->voice_count;i++) if(!poly->voices[i].active){ v=&poly->voices[i]; break; }
    if(!v){
        /* voice stealing: quietest */
        float min_gain=10; int min_idx=0;
        for(int i=0;i<poly->voice_count;i++){
            if(poly->voices[i].gain < min_gain){ min_gain=poly->voices[i].gain; min_idx=i; }
        }
        v=&poly->voices[min_idx];
    }
    v->sample=&z->sample;
    float semi = (midi - z->root_midi) + z->tune_cents/100.0f;
    float pan = z->pan + ag_rng_range_f32(&poly->rng, -0.05f, 0.05f);
    ag_sampler_voice_play(v, semi, vel * z->gain, pan);
}
void ag_sampler_poly_note_off(AgSamplerPoly *poly, int midi) {
    /* find voices playing this midi (approx via sample) - for simplicity stop first */
    (void)midi;
    for(int i=0;i<poly->voice_count;i++) if(poly->voices[i].active){
        /* quick release */
        poly->voices[i].active=0;
        break;
    }
}
float ag_sampler_poly_next(AgSamplerPoly *poly) {
    float mix=0;
    for(int i=0;i<poly->voice_count;i++) if(poly->voices[i].active) mix+=ag_sampler_voice_next(&poly->voices[i]);
    mix = tanhf(mix*0.8f)*1.1f;
    return mix * poly->gain;
}
void ag_sampler_poly_next_stereo(AgSamplerPoly *poly, float *l, float *r) {
    float ml=0,mr=0;
    for(int i=0;i<poly->voice_count;i++) if(poly->voices[i].active){
        float sl,sr; ag_sampler_voice_next_stereo(&poly->voices[i], &sl, &sr);
        ml+=sl; mr+=sr;
    }
    /* bus soft clip */
    ml = tanhf(ml*0.8f)*1.1f;
    mr = tanhf(mr*0.8f)*1.1f;
    *l=ml*poly->gain; *r=mr*poly->gain;
}

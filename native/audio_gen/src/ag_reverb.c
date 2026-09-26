#include "ag_reverb.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>

/* HQ Freeverb with modulation, stereo, early reflections */

static int comb_tunings[AG_REVERB_COMBS] = {1116,1188,1277,1356,1422,1491,1557,1617};
static int allp_tunings[AG_REVERB_ALLP] = {556,441,341,225};
static int early_tunings[4] = {53, 83, 137, 197};

void ag_reverb_init(AgReverb *rv, int sr) {
    memset(rv,0,sizeof(*rv));
    rv->sr = sr>0?sr:AG_SR_DEFAULT;
    rv->room_size = 0.5f;
    rv->damping = 0.5f;
    rv->wet = 0.33f;
    rv->dry = 0.0f;
    rv->width = 1.0f;
    rv->gain = 0.9f;
    rv->mod_depth = 0.008f;
    rv->mod_freq = 0.8f;
    double scale = (double)rv->sr / 44100.0;
    for (int i=0;i<AG_REVERB_COMBS;i++) {
        int sz = (int)(comb_tunings[i]*scale);
        if (sz<20) sz=20;
        /* add extra for modulation */
        sz += 16;
        rv->comb_bufs[i] = (float*)calloc(sz, sizeof(float));
        rv->combs[i].buf = rv->comb_bufs[i];
        rv->combs[i].size = sz;
        rv->combs[i].feedback = 0.84f;
        rv->combs[i].damp = 0.2f;
        rv->comb_mod_phase[i] = (float)i * 0.7f;
    }
    for (int i=0;i<AG_REVERB_ALLP;i++) {
        int sz = (int)(allp_tunings[i]*scale);
        if (sz<10) sz=10;
        rv->allp_bufs[i] = (float*)calloc(sz, sizeof(float));
        rv->allps[i].buf = rv->allp_bufs[i];
        rv->allps[i].size = sz;
        rv->allps[i].feedback = 0.5f;
    }
    /* early */
    for(int i=0;i<4;i++){
        int sz = (int)(early_tunings[i]*scale);
        if(sz<10) sz=10;
        rv->early_bufs[i]=(float*)calloc(sz,sizeof(float));
        rv->early_sizes[i]=sz;
        rv->early_pos[i]=0;
    }
    rv->initialized=1;
    ag_reverb_set_room_size(rv, rv->room_size);
    ag_reverb_set_damping(rv, rv->damping);
}
void ag_reverb_free(AgReverb *rv) {
    if (!rv->initialized) return;
    for (int i=0;i<AG_REVERB_COMBS;i++) free(rv->comb_bufs[i]);
    for (int i=0;i<AG_REVERB_ALLP;i++) free(rv->allp_bufs[i]);
    for(int i=0;i<4;i++) free(rv->early_bufs[i]);
    rv->initialized=0;
}
void ag_reverb_set_room_size(AgReverb *rv, float room_size) {
    rv->room_size = ag_clamp_f(room_size,0,1);
    for (int i=0;i<AG_REVERB_COMBS;i++){
        float base = 0.28f + rv->room_size*0.7f;
        /* slightly different per comb for diffusion */
        base += (i%3)*0.015f;
        if(base>0.98f) base=0.98f;
        rv->combs[i].feedback = base;
    }
}
void ag_reverb_set_damping(AgReverb *rv, float damping) {
    rv->damping = ag_clamp_f(damping,0,1);
    for (int i=0;i<AG_REVERB_COMBS;i++){
        /* frequency-dependent damping: more damping for high */
        float d = rv->damping * (0.35f + (i%4)*0.05f);
        if(d>0.9f) d=0.9f;
        rv->combs[i].damp = d;
    }
}
void ag_reverb_set_wet(AgReverb *rv, float wet) { rv->wet = ag_clamp_f(wet,0,1); }
void ag_reverb_set_dry(AgReverb *rv, float dry) { rv->dry = ag_clamp_f(dry,0,1); }
void ag_reverb_set_width(AgReverb *rv, float width) { rv->width = ag_clamp_f(width,0,1); }
void ag_reverb_set_gain(AgReverb *rv, float gain) { rv->gain = gain; }

static float comb_process_hq(AgComb *c, float in, float mod_offset) {
    /* mod_offset is fractional delay modulation */
    int size = c->size;
    int pos = c->pos;
    /* read with modulation */
    float read_pos = (float)pos + mod_offset;
    int i0 = (int)floorf(read_pos);
    float frac = read_pos - (float)i0;
    i0 = (i0 % size + size) % size;
    int i1 = (i0+1)%size;
    float out = c->buf[i0]*(1.0f-frac) + c->buf[i1]*frac;
    /* low-pass damping */
    c->filter_store = out * (1.0f - c->damp) + c->filter_store * c->damp;
    c->buf[c->pos] = in + c->filter_store * c->feedback;
    c->pos = (c->pos+1)%c->size;
    return out;
}
static float allp_process(AgAllpass *a, float in) {
    float bufout = a->buf[a->pos];
    float out = -in + bufout;
    a->buf[a->pos] = in + bufout * a->feedback;
    a->pos = (a->pos+1)%a->size;
    return out;
}

float ag_reverb_process(AgReverb *rv, float in) {
    if (!rv->initialized) return in;
    float out=0.0f;
    /* modulation */
    rv->mod_phase += rv->mod_freq / rv->sr;
    if(rv->mod_phase>1.0f) rv->mod_phase-=1.0f;
    for (int i=0;i<AG_REVERB_COMBS;i++){
        float mod = sinf((rv->mod_phase + rv->comb_mod_phase[i])*2.0f*(float)AG_PI) * rv->mod_depth * rv->combs[i].size;
        out += comb_process_hq(&rv->combs[i], in, mod);
    }
    out *= 0.125f; /* 8 combs */
    /* early reflections: add small delays */
    float early=0;
    for(int i=0;i<4;i++){
        float *buf=rv->early_bufs[i];
        int pos=rv->early_pos[i];
        early += buf[pos]*0.25f;
        buf[pos]=in*0.3f;
        rv->early_pos[i]=(pos+1)%rv->early_sizes[i];
    }
    out = out*0.85f + early*0.25f;
    for (int i=0;i<AG_REVERB_ALLP;i++) out = allp_process(&rv->allps[i], out);
    /* soft saturation for warmth */
    out = tanhf(out*1.1f)*0.9f;
    return out * rv->gain;
}
void ag_reverb_process_stereo(AgReverb *rv, float in_l, float in_r, float *out_l, float *out_r) {
    float mono = (in_l + in_r)*0.5f;
    float side = (in_l - in_r)*0.5f;
    /* process mono through reverb */
    float rev_mono = ag_reverb_process(rv, mono);
    /* process side with slightly different modulation for width */
    rv->mod_phase += 0.0001f; /* offset */
    float rev_side = ag_reverb_process(rv, side*0.7f) * 0.6f;
    rv->mod_phase -= 0.0001f;

    /* width control: wet1 = wet*(1+width*0.5), wet2 = wet*(1-width*0.5) but with side */
    float wet = rv->wet;
    float width = rv->width;
    float dry = rv->dry;

    /* M/S to L/R */
    float rev_l = rev_mono + rev_side*width;
    float rev_r = rev_mono - rev_side*width;

    *out_l = in_l * dry + rev_l * wet;
    *out_r = in_r * dry + rev_r * wet;
}
void ag_reverb_process_block(AgReverb *rv, float *buf, int frames) {
    for (int i=0;i<frames;i++) {
        float in = buf[i];
        float rev = ag_reverb_process(rv, in);
        buf[i] = in*rv->dry + rev*rv->wet;
    }
}
void ag_reverb_process_block_stereo(AgReverb *rv, float *interleaved, int frames) {
    for (int i=0;i<frames;i++) {
        float l = interleaved[i*2];
        float r = interleaved[i*2+1];
        float ol,or_;
        ag_reverb_process_stereo(rv,l,r,&ol,&or_);
        interleaved[i*2]=ol;
        interleaved[i*2+1]=or_;
    }
}

/* Schroeder HQ */
void ag_schroeder_init(AgSchroeder *rv, int sr) {
    memset(rv,0,sizeof(*rv));
    rv->sr = sr>0?sr:AG_SR_DEFAULT;
    rv->wet=0.3f; rv->dry=0.7f;
    int combs[4]={1557,1617,1491,1422};
    int allps[2]={225,556};
    double scale = (double)rv->sr/44100.0;
    for (int i=0;i<4;i++) {
        int sz = (int)(combs[i]*scale);
        if (sz<10) sz=10;
        sz+=8;
        rv->comb_bufs[i]=(float*)calloc(sz,sizeof(float));
        rv->comb_sizes[i]=sz;
        rv->comb_fb[i]=0.84f;
    }
    for (int i=0;i<2;i++) {
        int sz=(int)(allps[i]*scale);
        if (sz<10) sz=10;
        rv->allp_bufs[i]=(float*)calloc(sz,sizeof(float));
        rv->allp_sizes[i]=sz;
    }
    rv->initialized=1;
}
void ag_schroeder_free(AgSchroeder *rv) {
    if (!rv->initialized) return;
    for (int i=0;i<4;i++) free(rv->comb_bufs[i]);
    for (int i=0;i<2;i++) free(rv->allp_bufs[i]);
    rv->initialized=0;
}
float ag_schroeder_process(AgSchroeder *rv, float in) {
    if (!rv->initialized) return in;
    float out=0;
    for (int i=0;i<4;i++) {
        float *buf=rv->comb_bufs[i];
        int pos=rv->comb_pos[i];
        float o=buf[pos];
        /* simple low-pass */
        float filtered = o*0.7f + rv->comb_filter[i]*0.3f;
        rv->comb_filter[i]=filtered;
        buf[pos]=in + filtered*rv->comb_fb[i];
        rv->comb_pos[i]=(pos+1)%rv->comb_sizes[i];
        out+=o;
    }
    out*=0.25f;
    for (int i=0;i<2;i++) {
        float *buf=rv->allp_bufs[i];
        int pos=rv->allp_pos[i];
        float bufout=buf[pos];
        float o = -out + bufout;
        buf[pos]=out + bufout*0.5f;
        rv->allp_pos[i]=(pos+1)%rv->allp_sizes[i];
        out=o;
    }
    out = tanhf(out*0.9f)*1.05f;
    return out*rv->wet + in*rv->dry;
}

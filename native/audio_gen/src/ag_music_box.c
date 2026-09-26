#include "ag_music_box.h"
#include <math.h>
#include <string.h>

void ag_ks_init(AgKarplus *ks, double sr) {
    memset(ks,0,sizeof(*ks));
    ks->sr = sr>0?sr:AG_SR_DEFAULT;
    ks->feedback = 0.996f;
    ks->damping = 0.42f;
    ks->gain = 0.72f;
    ag_biquad_init(&ks->filter);
    ag_biquad_init(&ks->filter2);
    ag_biquad_set(&ks->filter, AG_FILTER_LP, 4200.0f, 0.72f, 0, (float)sr);
    ag_biquad_set(&ks->filter2, AG_FILTER_HP, 30.0f, 0.7f, 0, (float)sr);
    ag_dcblock_init(&ks->dc);
    ks->ap_coeff=0.3f;
}
void ag_ks_pluck(AgKarplus *ks, float freq, float damping, float gain) {
    if (freq < 15) freq=15;
    if(freq> ks->sr*0.45f) freq=ks->sr*0.45f;
    int len = (int)(ks->sr / freq);
    if (len < 4) len=4;
    if (len > AG_KS_MAX_DELAY) len=AG_KS_MAX_DELAY;
    ks->buf_len = len;
    ks->pos = 0;
    ks->damping = ag_clamp_f(damping,0,0.995f);
    ks->gain = gain;
    ks->ap_pos=0;
    AgRng rng; ag_rng_seed(&rng, (uint64_t)(freq*1000) ^ 0x1234 ^ (uint64_t)(gain*1000));
    for (int i=0;i<len;i++){
        float v = ag_rng_range_f32(&rng, -1.0f, 1.0f);
        /* shape for brighter pluck */
        v = v*0.6f + powf(fabsf(v),1.5f)*(v>0?1:-1)*0.4f;
        ks->buf[i]=v;
    }
    ks->active=1;
    /* set filter based on freq */
    float lp_fc = freq*3.2f + 1200.0f;
    if(lp_fc>12000) lp_fc=12000;
    ag_biquad_set(&ks->filter, AG_FILTER_LP, lp_fc, 0.72f, 0, (float)ks->sr);
}
float ag_ks_next(AgKarplus *ks) {
    if (!ks->active) return 0.0f;
    float cur = ks->buf[ks->pos];
    int next = (ks->pos+1)%ks->buf_len;
    float nxt = ks->buf[next];
    /* 2-point avg with allpass for tuning */
    float avg = (cur + nxt) * 0.5f;
    /* allpass for fractional tuning */
    float ap_out = avg + ks->ap_coeff * ks->ap_last;
    float ap_in = avg;
    ks->ap_last = ap_in - ks->ap_coeff * ap_out;
    avg = ap_out;
    avg = ag_biquad_process_hq(&ks->filter, avg);
    avg = ag_biquad_process_hq(&ks->filter2, avg);
    avg *= ks->feedback;
    /* damping as low-pass in loop */
    float damp = ks->damping;
    avg = avg * (1.0f - damp*0.15f) + cur * damp*0.02f;
    ks->buf[ks->pos] = avg;
    ks->pos = next;
    /* check decay */
    if (fabsf(avg) < 0.00015f) {
        float sum=0;
        for(int i=0;i<ks->buf_len;i++) sum+=fabsf(ks->buf[i]);
        if (sum < 0.002f) ks->active=0;
    }
    float out = cur * ks->gain;
    out = ag_dcblock_process(&ks->dc, out);
    return out;
}
int ag_ks_active(const AgKarplus *ks) { return ks->active; }

void ag_tine_init(AgTine *t, double sr) {
    memset(t,0,sizeof(*t));
    t->sr = sr>0?sr:AG_SR_DEFAULT;
    t->gain=0.62f;
    ag_osc_init(&t->osc, AG_OSC_SINE, sr);
    ag_osc_init(&t->overtone, AG_OSC_SINE, sr);
    ag_osc_init(&t->overtone2, AG_OSC_SINE, sr);
    AgADSR adsr = {0.0008f, 0.85f, 0.0f, 0.22f, 0.25f, 2.1f, 1.05f,1,0.08f};
    ag_env_init(&t->env, adsr, sr);
    ag_biquad_init(&t->filter);
    ag_biquad_init(&t->filter2);
    ag_biquad_set(&t->filter, AG_FILTER_LP, 4200.0f, 0.72f, 0, (float)sr);
    ag_biquad_set(&t->filter2, AG_FILTER_HP, 80.0f, 0.7f, 0, (float)sr);
    ag_dcblock_init(&t->dc);
}
void ag_tine_hit(AgTine *t, float freq, float vel) {
    if (freq<15) freq=15;
    ag_osc_set_freq(&t->osc, freq);
    ag_osc_set_freq(&t->overtone, freq*4.02f);
    ag_osc_set_freq(&t->overtone2, freq*8.1f);
    t->osc.phase=0; t->overtone.phase=0; t->overtone2.phase=0;
    ag_env_trigger_vel(&t->env, vel);
    t->active=1;
    t->vel=ag_clamp_f(vel,0,1);
    ag_biquad_set(&t->filter, AG_FILTER_LP, freq*6.5f, 0.72f, 0, (float)t->sr);
}
float ag_tine_next(AgTine *t) {
    if (!t->active) return 0.0f;
    float env = ag_env_next_hq(&t->env);
    if (ag_env_is_idle(&t->env)) { t->active=0; return 0.0f; }
    float s1 = ag_osc_next(&t->osc);
    float s2 = ag_osc_next(&t->overtone) * 0.32f * env;
    float s3 = ag_osc_next(&t->overtone2) * 0.12f * env * env;
    float out = (s1*0.75f + s2*0.28f + s3*0.12f) * env;
    out = ag_biquad_process_hq(&t->filter, out);
    out = ag_biquad_process_hq(&t->filter2, out);
    out = ag_dcblock_process(&t->dc, out);
    return out * t->gain * (0.7f + t->vel*0.4f);
}
int ag_tine_active(const AgTine *t) { return t->active; }

void ag_bell_init(AgBell *b, double sr) {
    memset(b,0,sizeof(*b));
    b->sr = sr>0?sr:AG_SR_DEFAULT;
    b->gain=0.62f;
    for (int i=0;i<AG_BELL_PARTIALS;i++) {
        ag_osc_init(&b->partials[i], AG_OSC_SINE, sr);
        ag_biquad_init(&b->filters[i]);
        b->amps[i]=0.0f;
        b->decays[i]=1.0f;
        b->envs[i]=0.0f;
    }
    ag_dcblock_init(&b->dc);
}
void ag_bell_hit(AgBell *b, float freq, float vel) {
    if (freq<20) freq=20;
    float ratios[AG_BELL_PARTIALS] = {1.0f, 2.01f, 2.42f, 3.02f, 4.23f, 5.43f, 6.85f, 8.12f};
    float amps[AG_BELL_PARTIALS] = {1.0f,0.62f,0.42f,0.32f,0.21f,0.16f,0.11f,0.06f};
    float decays[AG_BELL_PARTIALS] = {1.0f,0.82f,0.71f,0.61f,0.51f,0.41f,0.31f,0.21f};
    for (int i=0;i<AG_BELL_PARTIALS;i++) {
        float f = freq*ratios[i] * (1.0f + ag_rng_range_f32(&b->rng, -0.002f, 0.002f));
        ag_osc_set_freq(&b->partials[i], f);
        b->partials[i].phase=ag_rng_next_f32(&b->rng)*0.1f;
        b->amps[i]=amps[i];
        b->decays[i]=decays[i];
        b->envs[i]=1.0f;
        ag_biquad_set(&b->filters[i], AG_FILTER_BP, f, 8.0f + i*2.0f, 0, (float)b->sr);
    }
    b->active=1;
    b->gain=0.62f*ag_clamp_f(vel,0,1);
    b->t=0.0;
    b->vel=vel;
}
float ag_bell_next(AgBell *b) {
    if (!b->active) return 0.0f;
    b->t += 1.0/b->sr;
    float out=0.0f;
    int alive=0;
    for (int i=0;i<AG_BELL_PARTIALS;i++) {
        if (b->envs[i]<=0.0001f) continue;
        alive=1;
        /* exponential decay */
        b->envs[i] *= expf(-1.0f / (b->decays[i]*b->sr*0.8f) * 2.5f);
        if (b->envs[i]<0.0001f) b->envs[i]=0;
        float s = ag_osc_next(&b->partials[i]) * b->amps[i] * b->envs[i];
        s = ag_biquad_process_hq(&b->filters[i], s);
        out += s;
    }
    if (!alive) b->active=0;
    out = ag_dcblock_process(&b->dc, out);
    out = tanhf(out*0.9f)*1.05f;
    return out * b->gain * 0.42f * (0.8f + b->vel*0.3f);
}
int ag_bell_active(const AgBell *b) { return b->active; }

void ag_kalimba_init(AgKalimba *k, double sr) {
    memset(k,0,sizeof(*k));
    ag_tine_init(&k->tine, sr);
    ag_ks_init(&k->wood, sr);
    k->mix=0.72f;
    ag_biquad_init(&k->body);
    ag_biquad_set(&k->body, AG_FILTER_BP, 800,1.2f,0,(float)sr);
}
void ag_kalimba_hit(AgKalimba *k, float freq, float vel) {
    ag_tine_hit(&k->tine, freq, vel);
    ag_ks_pluck(&k->wood, freq*0.5f, 0.32f, vel*0.32f);
    ag_biquad_set(&k->body, AG_FILTER_BP, freq*1.5f, 1.2f, 0, (float)k->tine.sr);
}
float ag_kalimba_next(AgKalimba *k) {
    float t = ag_tine_next(&k->tine);
    float w = ag_ks_next(&k->wood);
    float body = ag_biquad_process_hq(&k->body, t*0.5f + w*0.5f)*0.3f;
    return (t*k->mix + w*(1.0f-k->mix))*0.85f + body*0.25f;
}

void ag_musicbox_init(AgMusicBox *mb, double sr) {
    memset(mb,0,sizeof(*mb));
    mb->sr = sr>0?sr:AG_SR_DEFAULT;
    mb->gain=0.62f;
    for (int i=0;i<AG_MUSICBOX_VOICES;i++) ag_tine_init(&mb->voices[i], sr);
    ag_reverb_init(&mb->reverb, (int)sr);
    ag_reverb_set_wet(&mb->reverb, 0.18f);
    ag_reverb_set_dry(&mb->reverb, 0.85f);
    ag_reverb_set_room_size(&mb->reverb, 0.45f);
}
void ag_musicbox_add_note(AgMusicBox *mb, float time, int midi, float vel) {
    if (mb->note_count >= AG_MUSICBOX_NOTES) return;
    mb->notes[mb->note_count].time=time;
    mb->notes[mb->note_count].midi=midi;
    mb->notes[mb->note_count].vel=vel;
    mb->note_count++;
}
void ag_musicbox_clear(AgMusicBox *mb) { mb->note_count=0; mb->playhead=0; mb->next_note=0; }
void ag_musicbox_set_loop(AgMusicBox *mb, int loop) { mb->looping=loop; }
float ag_musicbox_next(AgMusicBox *mb) {
    mb->playhead += 1.0/mb->sr;
    while (mb->next_note < mb->note_count && mb->notes[mb->next_note].time <= mb->playhead) {
        int v=-1;
        for (int i=0;i<AG_MUSICBOX_VOICES;i++) if (!mb->voices[i].active) { v=i; break; }
        if (v==-1){
            float min_env=10; int min_i=0;
            for(int i=0;i<AG_MUSICBOX_VOICES;i++){
                float ev = (float)mb->voices[i].env.value;
                if(ev<min_env){ min_env=ev; min_i=i; }
            }
            v=min_i;
        }
        float freq = (float)ag_midi_to_freq(mb->notes[mb->next_note].midi);
        ag_tine_hit(&mb->voices[v], freq, mb->notes[mb->next_note].vel);
        mb->next_note++;
    }
    if (mb->next_note >= mb->note_count && mb->looping) {
        mb->playhead=0; mb->next_note=0;
    }
    float mix=0.0f;
    for (int i=0;i<AG_MUSICBOX_VOICES;i++) mix += ag_tine_next(&mb->voices[i]);
    float rev_l, rev_r;
    ag_reverb_process_stereo(&mb->reverb, mix*0.5f, mix*0.5f, &rev_l, &rev_r);
    float out = (rev_l+rev_r)*0.5f*0.85f + mix*0.5f;
    return out * mb->gain;
}
void ag_musicbox_render(AgMusicBox *mb, float *out, int frames) {
    for (int i=0;i<frames;i++) out[i]=ag_musicbox_next(mb);
}

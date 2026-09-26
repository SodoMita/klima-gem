#include "ag_drums.h"
#include <math.h>
#include <string.h>

void ag_drum_params_default(AgDrumParams *p, AgDrumType type) {
    memset(p,0,sizeof(*p));
    p->type = type;
    p->tune = 1.0f;
    p->gain = 0.82f;
    p->seed = 1;
    switch (type) {
        case AG_DRUM_KICK: p->decay=0.55f; p->snap=0.32f; p->noise_mix=0.04f; break;
        case AG_DRUM_SNARE: p->decay=0.32f; p->snap=0.52f; p->noise_mix=0.62f; break;
        case AG_DRUM_HIHAT_CLOSED: p->decay=0.09f; p->noise_mix=1.0f; p->gain=0.52f; break;
        case AG_DRUM_HIHAT_OPEN: p->decay=0.38f; p->noise_mix=1.0f; p->gain=0.52f; break;
        case AG_DRUM_CLAP: p->decay=0.28f; p->noise_mix=0.82f; break;
        case AG_DRUM_TOM_LOW: p->decay=0.42f; p->tune=0.7f; break;
        case AG_DRUM_TOM_MID: p->decay=0.36f; p->tune=1.0f; break;
        case AG_DRUM_TOM_HIGH: p->decay=0.31f; p->tune=1.5f; break;
        case AG_DRUM_RIM: p->decay=0.09f; p->snap=0.82f; break;
        case AG_DRUM_COWBELL: p->decay=0.55f; p->tune=1.0f; break;
        case AG_DRUM_CYMBAL: p->decay=1.3f; p->noise_mix=0.72f; break;
        default: p->decay=0.32f; break;
    }
}

void ag_drum_voice_init(AgDrumVoice *v, const AgDrumParams *p, float sr) {
    memset(v,0,sizeof(*v));
    v->params = *p;
    v->sr = sr>0?sr:AG_SR_DEFAULT;
    v->active = 1;
    v->t = 0.0;
    ag_noise_init(&v->noise, p->seed ? p->seed : 0xD401A5);
    ag_noise_init(&v->noise2, p->seed ? p->seed+1 : 0xD401A6);
    ag_osc_init(&v->osc, AG_OSC_SINE, v->sr);
    ag_osc_init(&v->osc2, AG_OSC_SINE, v->sr);
    ag_osc_init(&v->osc_click, AG_OSC_SINE, v->sr);
    ag_biquad_init(&v->filter);
    ag_biquad_init(&v->filter2);
    ag_biquad_init(&v->filter_hp);
    ag_dcblock_init(&v->dc_block);

    float base_freq = 50.0f;
    switch (p->type) {
        case AG_DRUM_KICK: base_freq = 58.0f * p->tune; break;
        case AG_DRUM_SNARE: base_freq = 175.0f * p->tune; break;
        case AG_DRUM_TOM_LOW: base_freq = 88.0f * p->tune; break;
        case AG_DRUM_TOM_MID: base_freq = 138.0f * p->tune; break;
        case AG_DRUM_TOM_HIGH: base_freq = 218.0f * p->tune; break;
        case AG_DRUM_RIM: base_freq = 1200.0f * p->tune; break;
        case AG_DRUM_COWBELL: base_freq = 540.0f * p->tune; break;
        default: base_freq = 200.0f * p->tune; break;
    }
    ag_osc_set_freq(&v->osc, base_freq);
    ag_osc_set_freq(&v->osc2, base_freq*1.52f);
    ag_osc_set_freq(&v->osc_click, base_freq*8.0f);

    AgADSR adsr_amp = ag_adsr_perc(p->decay);
    if (p->type==AG_DRUM_KICK) { adsr_amp.attack=0.0008f; adsr_amp.decay=p->decay; adsr_amp.attack_shape=1; adsr_amp.punch=0.18f; }
    if (p->type==AG_DRUM_HIHAT_CLOSED || p->type==AG_DRUM_HIHAT_OPEN) {
        adsr_amp.attack=0.0005f;
    }
    if (p->type==AG_DRUM_SNARE) { adsr_amp.attack=0.0006f; adsr_amp.decay=p->decay; }
    ag_env_init(&v->env_amp, adsr_amp, v->sr);
    ag_env_trigger(&v->env_amp);

    AgADSR adsr_pitch = {0.001f, 0.085f, 0.0f, 0.02f, 0.45f, 2.1f, 1.0f,1,0};
    ag_env_init(&v->env_pitch, adsr_pitch, v->sr);
    ag_env_trigger(&v->env_pitch);

    AgADSR adsr_noise = {0.0008f, p->decay*0.62f, 0.0f, 0.05f, 1.0f, 1.0f, 1.0f,0,0};
    ag_env_init(&v->env_noise, adsr_noise, v->sr);
    ag_env_trigger(&v->env_noise);

    AgADSR adsr_click = {0.0001f, 0.015f, 0.0f, 0.005f, 0.5f, 2.0f, 1.0f,0,0};
    ag_env_init(&v->env_click, adsr_click, v->sr);
    ag_env_trigger(&v->env_click);

    if (p->type==AG_DRUM_HIHAT_CLOSED || p->type==AG_DRUM_HIHAT_OPEN || p->type==AG_DRUM_CYMBAL) {
        ag_biquad_set(&v->filter, AG_FILTER_HP, 3800.0f, 0.72f, 0, (float)v->sr);
        ag_biquad_set(&v->filter2, AG_FILTER_HP, 7000.0f, 0.7f, 0, (float)v->sr);
        ag_biquad_set(&v->filter_hp, AG_FILTER_HP, 300.0f, 0.7f, 0, (float)v->sr);
    } else if (p->type==AG_DRUM_SNARE) {
        ag_biquad_set(&v->filter, AG_FILTER_BP, 1900.0f, 1.1f, 0, (float)v->sr);
        ag_biquad_set(&v->filter2, AG_FILTER_HP, 1200.0f, 0.7f, 0, (float)v->sr);
    } else if (p->type==AG_DRUM_KICK) {
        ag_biquad_set(&v->filter, AG_FILTER_LP, 180.0f, 0.8f, 0, (float)v->sr);
    }
}

int ag_drum_voice_active(const AgDrumVoice *v) { return v->active; }

float ag_drum_voice_next(AgDrumVoice *v) {
    if (!v->active) return 0.0f;
    double dt = 1.0 / v->sr;
    v->t += dt;

    float env_amp = ag_env_next_hq(&v->env_amp);
    float env_pitch = ag_env_next_hq(&v->env_pitch);
    float env_noise = ag_env_next_hq(&v->env_noise);
    float env_click = ag_env_next_hq(&v->env_click);

    if (ag_env_is_idle(&v->env_amp) && env_amp <= 0.0002f) {
        v->active = 0;
        return 0.0f;
    }

    float out = 0.0f;
    float base_freq = (float)v->osc.freq;

    switch (v->params.type) {
        case AG_DRUM_KICK: {
            /* 3-stage pitch: fast drop 150->60, then slower */
            float pitch_env = 1.0f + env_pitch*5.5f + env_click*2.0f;
            ag_osc_set_freq(&v->osc, base_freq * pitch_env);
            float sine = ag_osc_next(&v->osc);
            /* second harmonic for body */
            float sine2 = sinf((float)(v->osc.phase*AG_TAU*2.0))*0.22f * env_amp;
            /* click: filtered noise + sine burst */
            float click = 0.0f;
            if (v->t < 0.008) {
                float click_sine = ag_osc_next(&v->osc_click) * env_click * 0.6f;
                float click_noise = ag_noise_white(&v->noise)*0.4f * env_click;
                click = (click_sine + click_noise) * v->params.snap * 1.2f;
            }
            /* low-end boost */
            float low = ag_biquad_process(&v->filter, sine);
            out = low*0.75f + sine*0.35f + sine2*0.3f + click;
            /* punch via soft clip + saturation */
            out = tanhf(out * 1.9f) * 0.68f;
            out += out*out*out*0.08f; /* subtle cubic */
        } break;
        case AG_DRUM_SNARE: {
            float pitch_mod = 1.0f + env_pitch*0.6f;
            ag_osc_set_freq(&v->osc, base_freq * pitch_mod);
            float tone = ag_osc_next(&v->osc) * 0.52f;
            tone = ag_biquad_process(&v->filter2, tone);
            /* noise with two layers */
            float noise_white = ag_noise_white(&v->noise);
            float noise_pink = ag_noise_pink_hq(&v->noise2)*0.5f;
            float noise = (noise_white*0.7f + noise_pink*0.3f);
            noise = ag_biquad_process(&v->filter, noise);
            noise *= env_noise;
            /* snap: high freq transient */
            float snap = ag_noise_white(&v->noise) * v->params.snap * expf(-(float)v->t*90.0f) * 0.6f;
            snap = ag_biquad_process(&v->filter2, snap);
            out = tone * (1.0f - v->params.noise_mix) * env_amp + noise * v->params.noise_mix + snap*env_click;
            /* body */
            out = ag_dcblock_process(&v->dc_block, out);
        } break;
        case AG_DRUM_HIHAT_CLOSED:
        case AG_DRUM_HIHAT_OPEN: {
            /* 6 detuned squares for metallic */
            float metal = 0.0f;
            double freqs[6] = {3047, 4007, 5230, 6523, 7437,  8932};
            for (int i=0;i<6;i++) {
                double f = freqs[i] * (0.98 + (i*0.02));
                v->osc.phase += f / v->sr;
                if (v->osc.phase>=1.0) v->osc.phase-=1.0;
                float sq = v->osc.phase < 0.5 ? 1.0f : -1.0f;
                /* polyBLEP */
                double dt2 = f / v->sr;
                sq += ag_poly_blep_4((float)v->osc.phase, (float)dt2);
                double ph2 = v->osc.phase - 0.5;
                if(ph2<0) ph2+=1.0;
                sq -= ag_poly_blep_4((float)ph2, (float)dt2);
                metal += sq;
            }
            metal *= 0.1666667f;
            float n1 = ag_noise_white(&v->noise)*0.6f + ag_noise_blue(&v->noise)*0.4f;
            float n = n1*0.55f + metal*0.45f;
            n = ag_biquad_process(&v->filter, n);
            n = ag_biquad_process(&v->filter2, n);
            n = ag_biquad_process(&v->filter_hp, n);
            out = n * env_amp;
            /* choked */
            if(v->params.type==AG_DRUM_HIHAT_CLOSED) out *= 0.9f;
        } break;
        case AG_DRUM_CLAP: {
            v->clap_timer += dt;
            if (v->clap_burst < 4 && v->clap_timer > 0.028) {
                v->clap_burst++;
                v->clap_timer = 0.0;
                ag_env_trigger(&v->env_noise);
                /* vary filter */
                float fc = 1100.0f + v->clap_burst*280.0f + ag_rng_range_f32(&v->noise.rng, -100,100);
                ag_biquad_set(&v->filter, AG_FILTER_BP, fc, 1.3f, 0, (float)v->sr);
            }
            float noise = ag_noise_white(&v->noise)*0.7f + ag_noise_pink(&v->noise)*0.3f;
            noise = ag_biquad_process(&v->filter, noise);
            float noise2 = ag_biquad_process(&v->filter2, noise)*0.4f;
            out = (noise*0.7f + noise2*0.3f) * env_noise * env_amp;
        } break;
        case AG_DRUM_TOM_LOW:
        case AG_DRUM_TOM_MID:
        case AG_DRUM_TOM_HIGH: {
            float pitch_env = 1.0f + env_pitch * 1.35f;
            ag_osc_set_freq(&v->osc, base_freq * pitch_env);
            float s1 = ag_osc_next(&v->osc);
            ag_osc_set_freq(&v->osc2, base_freq * pitch_env * 1.52f);
            float s2 = ag_osc_next(&v->osc2)*0.32f;
            out = (s1*0.75f + s2*0.35f) * env_amp;
            /* stick click */
            float stick = expf(-(float)v->t*150.0f) * 0.25f * env_click;
            out += stick;
            out = tanhf(out*1.15f)*0.9f;
        } break;
        case AG_DRUM_RIM: {
            float sine = ag_osc_next(&v->osc) * 0.25f;
            float noise = ag_noise_white(&v->noise) * expf(-(float)v->t*130.0f) * 0.9f;
            noise = ag_biquad_process(&v->filter, noise);
            out = (sine + noise) * env_amp;
            out = ag_biquad_process(&v->filter2, out);
        } break;
        case AG_DRUM_COWBELL: {
            float s1 = ag_osc_next(&v->osc);
            float s2 = ag_osc_next(&v->osc2);
            /* add third partial */
            float s3 = sinf((float)(v->osc.phase*AG_TAU*1.98))*0.25f;
            out = (s1*0.5f + s2*0.38f + s3*0.18f) * env_amp;
            out = tanhf(out*1.1f)*0.85f;
        } break;
        case AG_DRUM_CYMBAL: {
            float noise = ag_noise_white(&v->noise)*0.5f + ag_noise_pink_hq(&v->noise2)*0.5f;
            noise = ag_biquad_process(&v->filter, noise);
            float metal = 0;
            for(int i=0;i<4;i++){
                double f = 2000 + i*1200 + i*300;
                v->osc.phase += f / v->sr;
                if(v->osc.phase>=1) v->osc.phase-=1;
                metal += v->osc.phase < 0.5 ? 1.0f : -1.0f;
            }
            metal*=0.25f;
            out = (noise*0.6f + metal*0.4f) * env_amp * 0.85f;
        } break;
        default: out = 0.0f; break;
    }

    if (v->params.type != AG_DRUM_SNARE && v->params.type != AG_DRUM_CLAP) {
        out *= env_amp;
    }

    out = ag_dcblock_process(&v->dc_block, out);
    return out * v->params.gain;
}

int ag_drum_render(const AgDrumParams *params, float *out, int max_frames, float sr) {
    if (!params || !out) return 0;
    AgDrumVoice v;
    ag_drum_voice_init(&v, params, sr);
    int i=0;
    for (; i<max_frames; i++) {
        if (!v.active) break;
        out[i] = ag_drum_voice_next(&v);
    }
    for (; i<max_frames; i++) out[i]=0.0f;
    return i;
}
int ag_drum_render_stereo(const AgDrumParams *params, float *stereo_interleaved, int max_frames, float sr) {
    if (!params || !stereo_interleaved) return 0;
    AgDrumVoice v;
    ag_drum_voice_init(&v, params, sr);
    int i=0;
    for (; i<max_frames; i++) {
        if (!v.active) break;
        float s = ag_drum_voice_next(&v);
        /* subtle stereo width */
        float l = s * (0.5f + (i%3)*0.02f);
        float r = s * (0.5f - (i%3)*0.015f);
        stereo_interleaved[i*2]=l;
        stereo_interleaved[i*2+1]=r;
    }
    for (; i<max_frames; i++) {
        stereo_interleaved[i*2]=0;
        stereo_interleaved[i*2+1]=0;
    }
    return i;
}

int ag_drum_kick(float *out, int max_frames, float sr, float tune) {
    AgDrumParams p; ag_drum_params_default(&p, AG_DRUM_KICK); p.tune=tune;
    return ag_drum_render(&p,out,max_frames,sr);
}
int ag_drum_snare(float *out, int max_frames, float sr, float tune) {
    AgDrumParams p; ag_drum_params_default(&p, AG_DRUM_SNARE); p.tune=tune;
    return ag_drum_render(&p,out,max_frames,sr);
}
int ag_drum_hihat(float *out, int max_frames, float sr, int open) {
    AgDrumParams p; ag_drum_params_default(&p, open?AG_DRUM_HIHAT_OPEN:AG_DRUM_HIHAT_CLOSED);
    return ag_drum_render(&p,out,max_frames,sr);
}
int ag_drum_clap(float *out, int max_frames, float sr) {
    AgDrumParams p; ag_drum_params_default(&p, AG_DRUM_CLAP);
    return ag_drum_render(&p,out,max_frames,sr);
}

void ag_drum_pattern_init(AgDrumPattern *pat, float bpm) {
    memset(pat,0,sizeof(*pat));
    pat->bpm = bpm>0?bpm:120.0f;
    pat->swing = 0.0f;
    for (int t=0;t<AG_DRUM_TRACKS;t++) {
        ag_drum_params_default(&pat->kits[t], (AgDrumType)(t % AG_DRUM_COUNT));
    }
}
void ag_drum_pattern_set_kit(AgDrumPattern *pat, int track, AgDrumType type) {
    if (track<0||track>=AG_DRUM_TRACKS) return;
    ag_drum_params_default(&pat->kits[track], type);
}
void ag_drum_pattern_set_step(AgDrumPattern *pat, int track, int step, int vel) {
    if (track<0||track>=AG_DRUM_TRACKS) return;
    if (step<0||step>=AG_DRUM_PATTERN_STEPS) return;
    pat->steps[track][step]=vel;
}
void ag_drum_machine_init(AgDrumMachine *dm, const AgDrumPattern *pat, float sr) {
    memset(dm,0,sizeof(*dm));
    dm->pattern = *pat;
    dm->sr = sr>0?sr:AG_SR_DEFAULT;
    dm->playhead = 0.0;
    dm->current_step = 0;
    dm->step_dur = 60.0 / pat->bpm / 4.0;
    dm->next_step_time = dm->step_dur;
    ag_rng_seed(&dm->rng, 0xD0101);
    for (int i=0;i<AG_DRUM_TRACKS;i++) dm->voices[i].active=0;
    dm->humanize=0.02f;
}
void ag_drum_machine_trigger_step(AgDrumMachine *dm, int step) {
    for (int tr=0;tr<AG_DRUM_TRACKS;tr++) {
        int vel = dm->pattern.steps[tr][step % AG_DRUM_PATTERN_STEPS];
        if (vel>0) {
            AgDrumParams p = dm->pattern.kits[tr];
            float vel_f = vel/100.0f;
            /* humanize velocity */
            vel_f += ag_rng_range_f32(&dm->rng, -dm->humanize, dm->humanize);
            vel_f = ag_clamp_f(vel_f, 0.2f, 1.0f);
            p.gain *= vel_f;
            /* humanize tune */
            p.tune *= 1.0f + ag_rng_range_f32(&dm->rng, -0.02f, 0.02f);
            ag_drum_voice_init(&dm->voices[tr], &p, (float)dm->sr);
        }
    }
}
float ag_drum_machine_next(AgDrumMachine *dm) {
    double dt = 1.0/dm->sr;
    dm->playhead += dt;
    if (dm->playhead >= dm->next_step_time) {
        dm->playhead = 0;
        dm->next_step_time = dm->step_dur;
        if (dm->pattern.swing>0 && (dm->current_step%2)==1) {
            dm->next_step_time += dm->step_dur * dm->pattern.swing;
        }
        /* humanize timing */
        dm->next_step_time += ag_rng_range_f32(&dm->rng, -dm->humanize*0.02, dm->humanize*0.02);
        ag_drum_machine_trigger_step(dm, dm->current_step);
        dm->current_step = (dm->current_step+1)%AG_DRUM_PATTERN_STEPS;
    }
    float mix=0.0f;
    for (int i=0;i<AG_DRUM_TRACKS;i++) {
        if (dm->voices[i].active) mix += ag_drum_voice_next(&dm->voices[i]);
    }
    /* bus compression / soft clip */
    mix = tanhf(mix*0.85f)*1.1f;
    return mix;
}
void ag_drum_machine_render(AgDrumMachine *dm, float *out, int frames) {
    for (int i=0;i<frames;i++) out[i]=ag_drum_machine_next(dm);
}

#include "ag_sfx.h"
#include <math.h>
#include <string.h>

void ag_sfx_params_init(AgSfxParams *p, uint64_t seed) {
    memset(p,0,sizeof(*p));
    p->wave = AG_SFX_SQUARE;
    p->base_freq = 440.0f;
    p->attack = 0.01f;
    p->sustain = 0.15f;
    p->decay = 0.2f;
    p->punch = 0.0f;
    p->duty = 0.5f;
    p->gain = 0.8f;
    p->lpf_freq = 2000.0f;
    p->hpf_freq = 0.0f;
    p->seed = seed ? seed : 1;
}

void ag_sfx_preset_coin(AgSfxParams *p) {
    ag_sfx_params_init(p, 0xC01A);
    p->wave = AG_SFX_SQUARE;
    p->base_freq = 800.0f;
    p->freq_ramp = 1200.0f;
    p->attack = 0.002f;
    p->sustain = 0.08f;
    p->decay = 0.12f;
    p->duty = 0.5f;
    p->gain = 0.7f;
}
void ag_sfx_preset_laser(AgSfxParams *p) {
    ag_sfx_params_init(p, 0x1A5E);
    p->wave = AG_SFX_SAW;
    p->base_freq = 1200.0f;
    p->freq_ramp = -2800.0f;
    p->attack = 0.005f;
    p->sustain = 0.1f;
    p->decay = 0.15f;
    p->gain = 0.7f;
}
void ag_sfx_preset_explosion(AgSfxParams *p) {
    ag_sfx_params_init(p, 0xB0057);
    p->wave = AG_SFX_NOISE;
    p->base_freq = 200.0f;
    p->freq_ramp = -120.0f;
    p->attack = 0.001f;
    p->sustain = 0.2f;
    p->decay = 0.5f;
    p->filter_on = 1;
    p->filter_type = AG_FILTER_LP;
    p->lpf_freq = 1200.0f;
    p->lpf_ramp = -2000.0f;
    p->lpf_resonance = 0.2f;
    p->gain = 0.9f;
}
void ag_sfx_preset_powerup(AgSfxParams *p) {
    ag_sfx_params_init(p, 0x50);
    p->wave = AG_SFX_SINE;
    p->base_freq = 300.0f;
    p->freq_ramp = 1800.0f;
    p->attack = 0.02f;
    p->sustain = 0.3f;
    p->decay = 0.3f;
    p->arp_speed = 0.12f;
    p->arp_mod = 12.0f;
    p->gain = 0.6f;
}
void ag_sfx_preset_hit(AgSfxParams *p) {
    ag_sfx_params_init(p, 0x1117);
    p->wave = AG_SFX_NOISE;
    p->base_freq = 600.0f;
    p->attack = 0.001f;
    p->sustain = 0.05f;
    p->decay = 0.08f;
    p->gain = 0.8f;
    p->filter_on = 1;
    p->lpf_freq = 3000.0f;
}
void ag_sfx_preset_jump(AgSfxParams *p) {
    ag_sfx_params_init(p, 0x5);
    p->wave = AG_SFX_SQUARE;
    p->base_freq = 400.0f;
    p->freq_ramp = 800.0f;
    p->attack = 0.01f;
    p->sustain = 0.12f;
    p->decay = 0.1f;
    p->duty = 0.3f;
    p->duty_ramp = 0.2f;
    p->gain = 0.6f;
}
void ag_sfx_preset_blip(AgSfxParams *p) {
    ag_sfx_params_init(p, 0xB11A);
    p->wave = AG_SFX_SINE;
    p->base_freq = 1000.0f;
    p->attack = 0.001f;
    p->sustain = 0.04f;
    p->decay = 0.04f;
    p->gain = 0.5f;
}
void ag_sfx_preset_click(AgSfxParams *p) {
    ag_sfx_params_init(p, 0xC1);
    p->wave = AG_SFX_SQUARE;
    p->base_freq = 1200.0f;
    p->attack = 0.0005f;
    p->sustain = 0.01f;
    p->decay = 0.02f;
    p->gain = 0.4f;
}
void ag_sfx_preset_sweep(AgSfxParams *p, float from_freq, float to_freq, float dur) {
    ag_sfx_params_init(p, 0x5EE9);
    p->wave = AG_SFX_SINE;
    p->base_freq = from_freq;
    float delta = to_freq - from_freq;
    if (dur < 0.001f) dur = 0.1f;
    p->freq_ramp = delta / dur;
    p->attack = dur * 0.1f;
    p->sustain = dur * 0.6f;
    p->decay = dur * 0.3f;
    p->gain = 0.6f;
}
void ag_sfx_preset_chime(AgSfxParams *p, int tone_count, float base_freq) {
    ag_sfx_params_init(p, 0xC41A3);
    p->wave = AG_SFX_SINE;
    p->base_freq = base_freq;
    p->attack = 0.005f;
    p->sustain = 0.15f;
    p->decay = 0.6f;
    p->arp_speed = 0.08f;
    p->arp_mod = 4.0f;
    p->gain = 0.5f;
    (void)tone_count;
}
void ag_sfx_preset_buzz(AgSfxParams *p) {
    ag_sfx_params_init(p, 0xB222);
    p->wave = AG_SFX_SAW;
    p->base_freq = 120.0f;
    p->vib_strength = 30.0f;
    p->vib_speed = 30.0f;
    p->attack = 0.01f;
    p->sustain = 0.2f;
    p->decay = 0.15f;
    p->gain = 0.6f;
}
void ag_sfx_preset_whoosh(AgSfxParams *p) {
    ag_sfx_params_init(p, 0xAAA);
    p->wave = AG_SFX_NOISE;
    p->base_freq = 1000.0f;
    p->filter_on = 1;
    p->filter_type = AG_FILTER_BP;
    p->lpf_freq = 800.0f;
    p->lpf_ramp = 2000.0f;
    p->attack = 0.1f;
    p->sustain = 0.2f;
    p->decay = 0.3f;
    p->gain = 0.6f;
}
void ag_sfx_preset_open(AgSfxParams *p) {
    ag_sfx_params_init(p, 0x0A1);
    p->wave = AG_SFX_SINE_SQUARE_MIX;
    p->base_freq = 420.0f;
    p->freq_ramp = 530.0f;
    p->attack = 0.01f;
    p->sustain = 0.05f;
    p->decay = 0.08f;
    p->gain = 0.5f;
}
void ag_sfx_preset_close(AgSfxParams *p) {
    ag_sfx_params_init(p, 0x0C1);
    p->wave = AG_SFX_SINE_SQUARE_MIX;
    p->base_freq = 900.0f;
    p->freq_ramp = -520.0f;
    p->attack = 0.01f;
    p->sustain = 0.05f;
    p->decay = 0.08f;
    p->gain = 0.5f;
}

void ag_sfx_voice_init(AgSfxVoice *v, const AgSfxParams *p, float sr) {
    memset(v,0,sizeof(*v));
    v->params = *p;
    v->base_freq = p->base_freq;
    v->current_duty = p->duty;
    v->t = 0.0;
    v->total_dur = p->attack + p->sustain + p->decay;
    if (v->total_dur < 0.01) v->total_dur = 0.2;
    v->active = 1;
    ag_rng_seed(&v->rng, p->seed);
    /* osc type mapping */
    AgOscType otype = AG_OSC_SINE;
    switch (p->wave) {
        case AG_SFX_SINE: otype = AG_OSC_SINE; break;
        case AG_SFX_SQUARE: otype = AG_OSC_SQUARE; break;
        case AG_SFX_SAW: otype = AG_OSC_SAW; break;
        case AG_SFX_TRI: otype = AG_OSC_TRI; break;
        case AG_SFX_NOISE: otype = AG_OSC_NOISE; break;
        case AG_SFX_SINE_SQUARE_MIX: otype = AG_OSC_SINE; break;
        default: otype = AG_OSC_SINE; break;
    }
    ag_osc_init(&v->osc, otype, sr);
    ag_osc_set_freq(&v->osc, v->base_freq);
    ag_osc_set_pw(&v->osc, v->current_duty);
    ag_osc_init(&v->vib_osc, AG_OSC_SINE, sr);
    ag_osc_set_freq(&v->vib_osc, p->vib_speed > 0 ? p->vib_speed : 6.0);
    ag_biquad_init(&v->lpf);
    ag_biquad_init(&v->hpf);
    if (p->filter_on) {
        if (p->lpf_freq > 0) ag_biquad_set(&v->lpf, p->filter_type, p->lpf_freq, p->lpf_resonance>0?p->lpf_resonance:0.7f, 0, sr);
        if (p->hpf_freq > 0) ag_biquad_set(&v->hpf, AG_FILTER_HP, p->hpf_freq, 0.7f, 0, sr);
    }
    AgAR ar; ar.attack = p->attack; ar.release = p->decay; ar.curve = 1.0f;
    ag_env_ar_init(&v->env, ar, sr);
    ag_env_ar_trigger(&v->env, v->total_dur);
}

int ag_sfx_voice_active(const AgSfxVoice *v) { return v->active; }

float ag_sfx_voice_next(AgSfxVoice *v) {
    if (!v->active) return 0.0f;
    double dt = 1.0 / v->osc.sr;
    v->t += dt;

    /* freq slide */
    float freq = v->base_freq + v->params.freq_ramp * (float)v->t + 0.5f * v->params.freq_dramp * (float)(v->t * v->t);
    /* vibrato */
    if (v->params.vib_strength > 0.01f) {
        float vib = ag_osc_next(&v->vib_osc) * v->params.vib_strength;
        freq += vib;
    }
    /* arp */
    if (v->params.arp_speed > 0.001f && v->params.arp_mod != 0.0f) {
        v->arp_t += dt;
        if (v->arp_t >= v->params.arp_speed) {
            v->arp_t = 0.0;
            v->arp_stage++;
            if (v->arp_stage > 3) v->arp_stage = 0;
        }
        if (v->arp_stage==1 || v->arp_stage==2) {
            float semi = v->params.arp_mod;
            if (v->arp_stage==2) semi *= 2.0f;
            freq *= powf(2.0f, semi/12.0f);
        }
    }
    if (freq < 20.0f) freq = 20.0f;
    if (freq > v->osc.sr*0.45f) freq = (float)(v->osc.sr*0.45f);
    ag_osc_set_freq(&v->osc, freq);

    /* duty ramp */
    v->current_duty += v->params.duty_ramp * (float)dt;
    v->current_duty = ag_clamp_f(v->current_duty, 0.05f, 0.95f);
    ag_osc_set_pw(&v->osc, v->current_duty);

    /* filter ramp */
    if (v->params.filter_on) {
        if (v->params.lpf_ramp != 0.0f && v->params.lpf_freq > 0) {
            float lf = v->params.lpf_freq + v->params.lpf_ramp * (float)v->t;
            if (lf < 10) lf = 10;
            if (lf > v->osc.sr*0.45f) lf = (float)(v->osc.sr*0.45f);
            ag_biquad_set(&v->lpf, v->params.filter_type, lf, 0.7f, 0, (float)v->osc.sr);
        }
        if (v->params.hpf_ramp != 0.0f && v->params.hpf_freq > 0) {
            float hf = v->params.hpf_freq + v->params.hpf_ramp * (float)v->t;
            if (hf < 10) hf = 10;
            ag_biquad_set(&v->hpf, AG_FILTER_HP, hf, 0.7f, 0, (float)v->osc.sr);
        }
    }

    /* envelope */
    float env = ag_env_ar_next(&v->env);
    /* punch */
    if (v->t < v->params.attack + v->params.sustain * 0.3f) {
        env += v->params.punch * (1.0f - (float)(v->t / (v->params.attack + v->params.sustain*0.3f)));
        if (env>1.0f) env=1.0f;
    }
    if (env <= 0.0001f && v->t > v->params.attack + v->params.sustain) {
        v->active = 0;
        return 0.0f;
    }

    float sample = 0.0f;
    if (v->params.wave == AG_SFX_SINE_SQUARE_MIX) {
        float s = sinf((float)(v->osc.phase * AG_TAU));
        v->osc.phase += v->osc.freq / v->osc.sr;
        if (v->osc.phase >= 1.0) v->osc.phase -= 1.0;
        float sq = v->osc.phase < v->current_duty ? 1.0f : -1.0f;
        sample = s*0.5f + sq*0.5f;
    } else {
        sample = ag_osc_next(&v->osc);
    }

    if (v->params.filter_on) {
        if (v->params.lpf_freq > 0) sample = ag_biquad_process(&v->lpf, sample);
        if (v->params.hpf_freq > 0) sample = ag_biquad_process(&v->hpf, sample);
    }

    /* phaser crude */
    if (v->params.phaser_offset != 0.0f || v->params.phaser_ramp != 0.0f) {
        v->phaser_phase += dt * (1.0 + v->params.phaser_ramp * v->t);
        float ph = sinf((float)(v->phaser_phase * AG_TAU)) * 0.5f + 0.5f;
        sample = sample * 0.7f + sample * ph * 0.3f;
    }

    return sample * env * v->params.gain;
}

int ag_sfx_render(const AgSfxParams *params, float *out, int max_frames, float sr) {
    if (!params || !out || max_frames<=0) return 0;
    AgSfxVoice voice;
    ag_sfx_voice_init(&voice, params, sr);
    int i=0;
    for (; i<max_frames; i++) {
        if (!voice.active) break;
        out[i] = ag_sfx_voice_next(&voice);
    }
    for (; i<max_frames; i++) out[i]=0.0f;
    return i;
}
int ag_sfx_render_stereo(const AgSfxParams *params, float *interleaved_stereo, int max_frames, float sr) {
    if (!params || !interleaved_stereo) return 0;
    AgSfxVoice voice;
    ag_sfx_voice_init(&voice, params, sr);
    int i=0;
    for (; i<max_frames; i++) {
        if (!voice.active) break;
        float s = ag_sfx_voice_next(&voice);
        interleaved_stereo[i*2] = s;
        interleaved_stereo[i*2+1] = s;
    }
    for (; i<max_frames; i++) {
        interleaved_stereo[i*2]=0; interleaved_stereo[i*2+1]=0;
    }
    return i;
}
int ag_sfx_render_preset_coin(float *out, int max_frames, float sr) {
    AgSfxParams p; ag_sfx_preset_coin(&p); return ag_sfx_render(&p,out,max_frames,sr);
}
int ag_sfx_render_preset_laser(float *out, int max_frames, float sr) {
    AgSfxParams p; ag_sfx_preset_laser(&p); return ag_sfx_render(&p,out,max_frames,sr);
}
int ag_sfx_render_preset_explosion(float *out, int max_frames, float sr) {
    AgSfxParams p; ag_sfx_preset_explosion(&p); return ag_sfx_render(&p,out,max_frames,sr);
}

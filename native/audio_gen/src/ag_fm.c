#include "ag_fm.h"
#include <math.h>
#include <string.h>

void ag_fm_op_init(AgFmOp *op, double sr, float freq_mul, float level) {
    memset(op,0,sizeof(*op));
    ag_osc_init(&op->osc, AG_OSC_SINE, sr);
    AgADSR adsr = ag_adsr_pad_hq();
    ag_env_init(&op->env, adsr, sr);
    op->freq_mul = freq_mul>0?freq_mul:1.0f;
    op->level = level;
    op->detune = 0.0f;
    op->feedback=0;
    op->last_out=0;
}

void ag_fm_voice2_init(AgFmVoice2 *v, double sr, float base_freq, float mod_index) {
    memset(v,0,sizeof(*v));
    v->sr = sr>0?sr:AG_SR_DEFAULT;
    v->mod_index = mod_index;
    v->gain = 0.7f;
    v->feedback = 0.0f;
    v->oversample=2;
    ag_fm_op_init(&v->mod, sr, 1.0f, 1.0f);
    ag_fm_op_init(&v->car, sr, 1.0f, 1.0f);
    ag_dcblock_init(&v->dc_block);
    (void)base_freq;
}
void ag_fm_voice2_note_on(AgFmVoice2 *v, float freq, float vel) {
    if (freq < 10) freq = 10;
    if(freq> v->sr*0.45f) freq = v->sr*0.45f;
    float mod_freq = freq * v->mod.freq_mul * powf(2.0f, v->mod.detune/1200.0f);
    float car_freq = freq * v->car.freq_mul * powf(2.0f, v->car.detune/1200.0f);
    ag_osc_set_freq(&v->mod.osc, mod_freq);
    ag_osc_set_freq(&v->car.osc, car_freq);
    ag_env_trigger_vel(&v->mod.env, vel);
    ag_env_trigger_vel(&v->car.env, vel);
    v->active = 1;
    v->gain = 0.72f * ag_clamp_f(vel,0,1);
    v->last_mod=0;
}
void ag_fm_voice2_note_off(AgFmVoice2 *v) {
    ag_env_release(&v->mod.env);
    ag_env_release(&v->car.env);
}
int ag_fm_voice2_active(const AgFmVoice2 *v) {
    return v->active && (!ag_env_is_idle(&v->car.env) || !ag_env_is_idle(&v->mod.env));
}
float ag_fm_voice2_next(AgFmVoice2 *v) {
    if (!ag_fm_voice2_active(v)) { v->active=0; return 0.0f; }
    /* 2x oversample for HQ FM */
    float out_acc=0;
    int os = v->oversample>0?v->oversample:2;
    if(os<1) os=1;
    if(os>8) os=8;
    for(int k=0;k<os;k++){
        float env_mod = ag_env_next_hq(&v->mod.env);
        float env_car = ag_env_next_hq(&v->car.env);
        /* modulator with feedback */
        float mod_fb = v->mod.last_out * v->mod.feedback * 0.5f;
        float mod_osc = sinf((float)(v->mod.osc.phase * AG_TAU)) * env_mod * v->mod.level;
        float mod_out = mod_osc + mod_fb;
        /* low-pass feedback for warmth */
        mod_out = mod_out*0.7f + v->mod.last_out*0.3f;
        v->mod.last_out = mod_out;
        v->last_mod = mod_out;

        float mod_phase = mod_out * v->mod_index;
        /* FM: carrier phase modulation with proper scaling */
        double car_inc = v->car.osc.freq / v->car.osc.sr / os;
        v->car.osc.phase += car_inc + mod_phase * 0.08f / os;
        while(v->car.osc.phase >= 1.0) v->car.osc.phase -= 1.0;
        while(v->car.osc.phase < 0) v->car.osc.phase += 1.0;
        float car = sinf((float)(v->car.osc.phase * AG_TAU)) * env_car * v->car.level;
        /* carrier feedback */
        if(v->car.feedback>0.001f){
            car += v->car.last_out * v->car.feedback * 0.3f;
        }
        v->car.last_out = car;
        out_acc += car;
        /* advance mod */
        v->mod.osc.phase += v->mod.osc.freq / v->mod.osc.sr / os;
        while(v->mod.osc.phase>=1.0) v->mod.osc.phase-=1.0;
    }
    float out = out_acc / os * v->gain;
    out = ag_dcblock_process(&v->dc_block, out);
    /* soft saturation for HQ */
    out = tanhf(out*1.05f)*0.95f;
    return out;
}

/* 4-op HQ */
void ag_fm_voice4_init(AgFmVoice4 *v, double sr, AgFmAlg4 alg) {
    memset(v,0,sizeof(*v));
    v->sr = sr>0?sr:AG_SR_DEFAULT;
    v->alg = alg;
    v->gain = 0.62f;
    v->oversample=2;
    for (int i=0;i<4;i++) ag_fm_op_init(&v->ops[i], sr, 1.0f + i*0.5f, 0.8f);
    ag_dcblock_init(&v->dc_block);
}
void ag_fm_voice4_note_on(AgFmVoice4 *v, float freq, float vel) {
    if (freq<10) freq=10;
    if(freq>v->sr*0.4f) freq=v->sr*0.4f;
    for (int i=0;i<4;i++) {
        float f = freq * v->ops[i].freq_mul * powf(2.0f, v->ops[i].detune/1200.0f);
        ag_osc_set_freq(&v->ops[i].osc, f);
        ag_env_trigger_vel(&v->ops[i].env, vel);
        v->ops[i].last_out=0;
    }
    v->active=1;
    v->gain=0.62f*ag_clamp_f(vel,0,1);
}
void ag_fm_voice4_note_off(AgFmVoice4 *v) {
    for (int i=0;i<4;i++) ag_env_release(&v->ops[i].env);
}
int ag_fm_voice4_active(const AgFmVoice4 *v) {
    for (int i=0;i<4;i++) if (!ag_env_is_idle(&v->ops[i].env)) return 1;
    return 0;
}
float ag_fm_voice4_next(AgFmVoice4 *v) {
    if (!ag_fm_voice4_active(v)) { v->active=0; return 0.0f; }
    float out_acc=0;
    int os = v->oversample>0?v->oversample:2;
    for(int k=0;k<os;k++){
        float env[4];
        float out_op[4];
        for (int i=0;i<4;i++) {
            env[i]=ag_env_next_hq(&v->ops[i].env);
            /* feedback */
            float fb = v->ops[i].last_out * v->ops[i].feedback * 0.4f;
            float osc = sinf((float)(v->ops[i].osc.phase*AG_TAU)) + fb;
            out_op[i]=osc * env[i] * v->ops[i].level;
            v->ops[i].last_out = out_op[i];
            /* advance phase */
            v->ops[i].osc.phase += v->ops[i].osc.freq / v->ops[i].osc.sr / os;
            while(v->ops[i].osc.phase>=1.0) v->ops[i].osc.phase-=1.0;
        }
        float out=0.0f;
        switch (v->alg) {
            case AG_FM_ALG_4_STACK: {
                /* true stack: each modulates next */
                float m1 = out_op[0];
                float p1 = v->ops[1].osc.phase + m1*0.12f;
                float m2 = sinf((float)(p1*AG_TAU)) * env[1] * v->ops[1].level;
                float p2 = v->ops[2].osc.phase + m2*0.12f;
                float m3 = sinf((float)(p2*AG_TAU)) * env[2] * v->ops[2].level;
                float p3 = v->ops[3].osc.phase + m3*0.12f;
                out = sinf((float)(p3*AG_TAU)) * env[3] * v->ops[3].level;
            } break;
            case AG_FM_ALG_3_PLUS_1: {
                float stack = out_op[0]*0.6f + out_op[1]*0.4f;
                float p2 = v->ops[2].osc.phase + stack*0.12f;
                float m = sinf((float)(p2*AG_TAU)) * env[2] * v->ops[2].level;
                out = m*0.65f + out_op[3]*0.38f;
            } break;
            case AG_FM_ALG_2x2: {
                float p1 = v->ops[1].osc.phase + out_op[0]*0.12f;
                float a = sinf((float)(p1*AG_TAU)) * env[1] * v->ops[1].level;
                float p3 = v->ops[3].osc.phase + out_op[2]*0.12f;
                float b = sinf((float)(p3*AG_TAU)) * env[3] * v->ops[3].level;
                out = (a + b)*0.52f;
            } break;
            default: {
                float sum = out_op[0]*0.3f+out_op[1]*0.3f+out_op[2]*0.3f;
                float p3 = v->ops[3].osc.phase + sum*0.12f;
                out = sinf((float)(p3*AG_TAU)) * env[3] * v->ops[3].level;
            } break;
        }
        out_acc+=out;
    }
    float out = out_acc / os * v->gain;
    out = ag_dcblock_process(&v->dc_block, out);
    out = tanhf(out*1.02f)*0.98f;
    return out;
}

void ag_fm_apply_preset_2op(AgFmVoice2 *v, AgFmPreset preset) {
    switch (preset) {
        case AG_FM_PRESET_BASS:
            v->mod.freq_mul=1.0f; v->car.freq_mul=1.0f;
            v->mod_index=2.6f; v->mod.level=0.92f; v->car.level=0.92f;
            v->mod.feedback=0.15f;
            v->mod.env.adsr = (AgADSR){0.008f,0.22f,0.62f,0.16f,0.8f,1.2f,1.0f,1,0.12f};
            v->car.env.adsr = (AgADSR){0.008f,0.22f,0.72f,0.22f,0.8f,1.2f,1.0f,1,0.08f};
            break;
        case AG_FM_PRESET_LEAD:
            v->mod.freq_mul=1.0f; v->car.freq_mul=1.0f;
            v->mod_index=4.2f; v->mod.level=1.0f; v->car.level=1.0f;
            v->mod.feedback=0.22f;
            v->mod.env.adsr = (AgADSR){0.018f,0.32f,0.82f,0.32f,1.0f,1.0f,1.0f,2,0};
            v->car.env.adsr = (AgADSR){0.018f,0.32f,0.82f,0.32f,1.0f,1.0f,1.0f,2,0};
            break;
        case AG_FM_PRESET_PAD:
            v->mod.freq_mul=0.5f; v->car.freq_mul=1.0f;
            v->mod_index=1.6f;
            v->mod.feedback=0.08f;
            v->mod.env.adsr = ag_adsr_pad_hq();
            v->car.env.adsr = ag_adsr_pad_hq();
            break;
        case AG_FM_PRESET_BELL:
            v->mod.freq_mul=3.51f; v->car.freq_mul=1.0f;
            v->mod_index=6.2f;
            v->mod.feedback=0.05f;
            v->mod.env.adsr = (AgADSR){0.0008f,1.25f,0.0f,0.32f,0.4f,1.6f,1.0f,1,0};
            v->car.env.adsr = (AgADSR){0.0008f,1.55f,0.0f,0.42f,0.4f,1.6f,1.0f,1,0};
            break;
        case AG_FM_PRESET_EPIANO:
            v->mod.freq_mul=1.0f; v->car.freq_mul=1.0f;
            v->mod_index=2.1f;
            v->mod.feedback=0.12f;
            v->mod.env.adsr = (AgADSR){0.004f,0.62f,0.22f,0.42f,0.9f,1.25f,1.0f,1,0};
            v->car.env.adsr = (AgADSR){0.004f,0.82f,0.32f,0.52f,0.9f,1.25f,1.0f,1,0};
            break;
        case AG_FM_PRESET_BRASS:
            v->mod.freq_mul=1.0f; v->car.freq_mul=1.0f;
            v->mod_index=3.1f;
            v->mod.feedback=0.18f;
            v->mod.env.adsr = (AgADSR){0.075f,0.22f,0.82f,0.22f,1.0f,1.0f,1.0f,2,0};
            v->car.env.adsr = (AgADSR){0.075f,0.22f,0.92f,0.27f,1.0f,1.0f,1.0f,2,0};
            break;
        default: break;
    }
}
void ag_fm_apply_preset_4op(AgFmVoice4 *v, AgFmPreset preset) {
    for (int i=0;i<4;i++) {
        v->ops[i].freq_mul = 1.0f + i*0.5f;
        v->ops[i].level = 0.82f;
        v->ops[i].feedback = 0.05f;
    }
    switch (preset) {
        case AG_FM_PRESET_BASS: v->alg=AG_FM_ALG_4_STACK; v->ops[0].feedback=0.2f; break;
        case AG_FM_PRESET_PAD: v->alg=AG_FM_ALG_2x2; v->ops[0].feedback=0.08f; v->ops[2].feedback=0.08f; break;
        case AG_FM_PRESET_BELL: v->alg=AG_FM_ALG_4_STACK; v->ops[0].freq_mul=3.51f; v->ops[0].feedback=0.02f; break;
        case AG_FM_PRESET_LEAD: v->alg=AG_FM_ALG_4_STACK; v->ops[0].feedback=0.25f; break;
        default: v->alg=AG_FM_ALG_2x2; break;
    }
}

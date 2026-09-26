#include "ag_envelope.h"
#include <math.h>
#include <string.h>

AgADSR ag_adsr_pluck(void) { AgADSR a={0.005f,0.25f,0.0f,0.15f,0.6f,1.2f,1.0f,0,0}; return a; }
AgADSR ag_adsr_pad(void) { AgADSR a={0.8f,0.6f,0.75f,1.2f,1.0f,1.0f,1.0f,0,0}; return a; }
AgADSR ag_adsr_bass(void) { AgADSR a={0.02f,0.15f,0.6f,0.25f,1.0f,1.0f,1.0f,0,0}; return a; }
AgADSR ag_adsr_stab(void) { AgADSR a={0.01f,0.35f,0.2f,0.4f,0.8f,1.5f,1.2f,0,0}; return a; }
AgADSR ag_adsr_perc(float decay) { AgADSR a={0.001f,decay,0.0f,0.05f,0.5f,2.0f,1.0f,0,0}; return a; }
AgADSR ag_adsr_pluck_hq(void) { AgADSR a={0.003f,0.28f,0.0f,0.18f,0.5f,1.3f,1.1f,1,0.15f}; return a; }
AgADSR ag_adsr_pad_hq(void) { AgADSR a={1.2f,0.8f,0.78f,1.5f,1.1f,0.9f,1.0f,2,0}; return a; }

void ag_env_init(AgEnv *env, AgADSR adsr, double sr) {
    memset(env,0,sizeof(*env));
    env->adsr = adsr;
    env->sr = sr>0?sr:AG_SR_DEFAULT;
    env->sample_rate_inv = 1.0 / env->sr;
    env->stage = AG_ENV_IDLE;
    env->value = 0.0;
    env->velocity=1.0f;
}
void ag_env_trigger(AgEnv *env) { ag_env_trigger_vel(env,1.0f); }
void ag_env_trigger_vel(AgEnv *env, float velocity) {
    env->stage = AG_ENV_ATTACK;
    env->time = 0.0;
    env->released = 0;
    env->start_value = env->value;
    env->target = 1.0;
    env->release_start_value = 0.0;
    env->velocity = ag_clamp_f(velocity,0,1);
    /* legato: if already active, start from current value */
    if(env->value>0.001 && env->adsr.attack <0.02f) env->legato=1;
    else env->legato=0;
}
void ag_env_release(AgEnv *env) {
    if (env->stage==AG_ENV_IDLE || env->stage==AG_ENV_RELEASE) return;
    env->released = 1;
    env->stage = AG_ENV_RELEASE;
    env->time = 0.0;
    env->start_value = env->value;
    env->release_start_value = env->value;
}
void ag_env_release_quick(AgEnv *env, float fade_ms) {
    if(env->stage==AG_ENV_IDLE) return;
    env->released=1;
    env->stage=AG_ENV_RELEASE;
    env->time=0;
    env->start_value=env->value;
    env->release_start_value=env->value;
    if(fade_ms>0.1f) env->adsr.release = fade_ms*0.001f;
    else env->adsr.release=0.005f;
}
int ag_env_is_active(const AgEnv *env) { return env->stage != AG_ENV_IDLE; }
int ag_env_is_idle(const AgEnv *env) { return env->stage == AG_ENV_IDLE; }
float ag_env_value(const AgEnv *env) { return (float)env->value; }

static double curve_shape(double t, double curve) {
    if (curve<=0.001) curve=0.001;
    if (fabs(curve-1.0)<0.001) return t;
    return pow(t, curve);
}
static double s_curve(double t) {
    /* smoothstep */
    return t*t*(3.0-2.0*t);
}
static double exp_curve(double t, double shape) {
    /* exponential with shape */
    if(shape<0.1) shape=0.1;
    if(shape>4) shape=4;
    return (exp(shape*t)-1.0)/(exp(shape)-1.0);
}

float ag_env_next(AgEnv *env) { return ag_env_next_hq(env); }

float ag_env_next_hq(AgEnv *env) {
    double dt = env->sample_rate_inv;
    double c = 1.0;
    double punch = env->adsr.punch;
    switch (env->stage) {
        case AG_ENV_IDLE:
            env->value = 0.0;
            break;
        case AG_ENV_ATTACK: {
            double a = env->adsr.attack > 0.00005 ? env->adsr.attack : 0.00005;
            c = env->adsr.attack_curve;
            if (c==0) c=1.0;
            double t = env->time / a;
            if (t>=1.0) {
                env->value = 1.0;
                env->stage = AG_ENV_DECAY;
                env->time = 0.0;
                env->start_value=1.0;
            } else {
                double sh;
                if(env->adsr.attack_shape==1) sh = exp_curve(t, c*2.0);
                else if(env->adsr.attack_shape==2) sh = s_curve(t);
                else sh = curve_shape(t, c);
                /* legato: start from current */
                if(env->legato) env->value = env->start_value + (1.0-env->start_value)*sh;
                else env->value = sh;
                /* punch */
                if(punch>0.01) env->value += punch * sin(t*AG_PI) * (1.0-t);
            }
        } break;
        case AG_ENV_DECAY: {
            double d = env->adsr.decay > 0.00005 ? env->adsr.decay : 0.00005;
            c = env->adsr.decay_curve;
            if (c==0) c=1.0;
            double t = env->time / d;
            if (t>=1.0) {
                env->value = env->adsr.sustain;
                env->stage = AG_ENV_SUSTAIN;
                env->time = 0.0;
                env->start_value=env->adsr.sustain;
            } else {
                double sh = curve_shape(t, c);
                if(env->adsr.attack_shape==2) sh = s_curve(t);
                env->value = 1.0 + (env->adsr.sustain - 1.0)*sh;
            }
        } break;
        case AG_ENV_SUSTAIN: {
            env->value = env->adsr.sustain;
            if (env->released) {
                env->stage = AG_ENV_RELEASE;
                env->time = 0.0;
                env->start_value = env->value;
                env->release_start_value = env->value;
            }
        } break;
        case AG_ENV_RELEASE: {
            double r = env->adsr.release > 0.00005 ? env->adsr.release : 0.00005;
            c = env->adsr.release_curve;
            if (c==0) c=1.0;
            double t = env->time / r;
            if (t>=1.0) {
                env->value = 0.0;
                env->stage = AG_ENV_IDLE;
            } else {
                double sh = curve_shape(t, c);
                if(env->adsr.attack_shape==2) sh = s_curve(t);
                /* exponential release for natural decay */
                double exp_rel = 1.0 - exp(-t*5.0);
                if(env->adsr.release_curve>1.2) sh = sh*0.5 + exp_rel*0.5;
                env->value = env->release_start_value * (1.0 - sh);
                /* de-click: ensure smooth to zero */
                if(t>0.9) env->value *= (1.0 - (t-0.9)*5.0*0.5);
            }
        } break;
    }
    env->time += dt;
    /* velocity scaling */
    double v = env->value * env->velocity;
    /* DC block for envelope to avoid click */
    float out = (float)v - env->dc_block*0.995f;
    env->dc_block = (float)v;
    /* but for envelope we want direct value, so return v */
    return (float)v;
}

/* AR HQ */
void ag_env_ar_init(AgEnvAR *env, AgAR ar, double sr) {
    memset(env,0,sizeof(*env));
    env->ar = ar;
    env->sr = sr>0?sr:AG_SR_DEFAULT;
}
void ag_env_ar_trigger(AgEnvAR *env, double duration) {
    env->t = 0.0;
    env->dur = duration>0?duration:1.0;
    env->active = 1;
    env->last=0;
}
float ag_env_ar_next(AgEnvAR *env) { return ag_env_ar_next_hq(env); }
float ag_env_ar_next_hq(AgEnvAR *env) {
    if (!env->active) return 0.0f;
    double dt = 1.0/env->sr;
    double a = env->ar.attack;
    double r = env->ar.release;
    if (a<0.00005) a=0.00005;
    if (r<0.00005) r=0.00005;
    double total = env->dur;
    double t = env->t;
    double v=0.0;
    if (t < a) {
        v = t / a;
        if (env->ar.curve!=1.0 && env->ar.curve!=0) v = pow(v, env->ar.curve);
        if(env->ar.shape==1) v = s_curve(v);
        else if(env->ar.shape==2) v = exp_curve(v, 2.0);
    } else if (t < total - r) {
        v = 1.0;
    } else if (t < total) {
        double rt = (t - (total - r))/r;
        v = 1.0 - rt;
        if (env->ar.curve!=1.0 && env->ar.curve!=0) v = pow(v, env->ar.curve);
        if(env->ar.shape==1) v = 1.0 - s_curve(1.0-v);
    } else {
        env->active = 0;
        v=0.0;
    }
    /* smoothing */
    float smooth = env->last*0.85f + (float)v*0.15f;
    env->last=smooth;
    env->t += dt;
    return smooth;
}

/* Multi HQ */
void ag_multi_env_init(AgMultiEnv *env, double sr) {
    memset(env,0,sizeof(*env));
    env->sr = sr>0?sr:AG_SR_DEFAULT;
}
void ag_multi_env_add_point(AgMultiEnv *env, float time, float value, float curve) {
    ag_multi_env_add_point_shape(env,time,value,curve,0);
}
void ag_multi_env_add_point_shape(AgMultiEnv *env, float time, float value, float curve, float shape) {
    if (env->count >= AG_ENV_MAX_POINTS) return;
    env->points[env->count].time = time;
    env->points[env->count].value = value;
    env->points[env->count].curve = curve;
    env->points[env->count].shape = shape;
    env->count++;
}
void ag_multi_env_trigger(AgMultiEnv *env) {
    env->t = 0.0;
    env->active = 1;
    env->last=env->count>0?env->points[0].value:0;
}
float ag_multi_env_next(AgMultiEnv *env) { return ag_multi_env_next_hq(env); }
float ag_multi_env_next_hq(AgMultiEnv *env) {
    if (!env->active || env->count==0) return 0.0f;
    double dt = 1.0/env->sr;
    double t = env->t;
    if (t >= env->points[env->count-1].time) {
        if (env->loop) {
            double loop_start = env->loop_start>=0 && env->loop_start<env->count ? env->points[env->loop_start].time : 0;
            env->t = loop_start;
            t=loop_start;
        }
        else { env->active=0; return env->points[env->count-1].value; }
    }
    int seg=0;
    for (int i=0;i<env->count-1;i++) {
        if (t >= env->points[i].time && t < env->points[i+1].time) { seg=i; break; }
    }
    AgEnvPoint *p0 = &env->points[seg];
    AgEnvPoint *p1 = &env->points[seg+1];
    double span = p1->time - p0->time;
    double frac = span>0 ? (t - p0->time)/span : 0.0;
    if (p0->curve!=1.0 && p0->curve!=0.0) frac = pow(frac, p0->curve);
    if(p0->shape==1) frac = s_curve(frac);
    else if(p0->shape==2) frac = exp_curve(frac, 2.0);
    float v = p0->value + (p1->value - p0->value)*(float)frac;
    /* smooth */
    float out = env->last*0.7f + v*0.3f;
    env->last=out;
    env->t += dt;
    return out;
}

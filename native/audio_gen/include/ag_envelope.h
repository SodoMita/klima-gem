#ifndef AG_ENVELOPE_H
#define AG_ENVELOPE_H

#include "ag_common.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    AG_ENV_IDLE = 0,
    AG_ENV_ATTACK,
    AG_ENV_DECAY,
    AG_ENV_SUSTAIN,
    AG_ENV_RELEASE
} AgEnvStage;

typedef struct AgADSR {
    float attack;
    float decay;
    float sustain;
    float release;
    float attack_curve;
    float decay_curve;
    float release_curve;
    float attack_shape; /* 0=lin,1=exp,2=s-curve */
    float punch;        /* 0..1 extra attack boost */
} AgADSR;

typedef struct AgEnv {
    AgADSR adsr;
    AgEnvStage stage;
    double time;
    double value;
    double target;
    double start_value;
    int released;
    double sr;
    double release_start_value;
    float velocity;     /* 0..1 */
    int legato;
    double sample_rate_inv;
    float dc_block;
} AgEnv;

AgADSR ag_adsr_pluck(void);
AgADSR ag_adsr_pad(void);
AgADSR ag_adsr_bass(void);
AgADSR ag_adsr_stab(void);
AgADSR ag_adsr_perc(float decay);
AgADSR ag_adsr_pluck_hq(void);
AgADSR ag_adsr_pad_hq(void);

void ag_env_init(AgEnv *env, AgADSR adsr, double sr);
void ag_env_trigger(AgEnv *env);
void ag_env_trigger_vel(AgEnv *env, float velocity);
void ag_env_release(AgEnv *env);
void ag_env_release_quick(AgEnv *env, float fade_ms);
int ag_env_is_active(const AgEnv *env);
int ag_env_is_idle(const AgEnv *env);
float ag_env_next(AgEnv *env);
float ag_env_next_hq(AgEnv *env); /* with punch and s-curve */
float ag_env_value(const AgEnv *env);

typedef struct AgAR {
    float attack;
    float release;
    float curve;
    float shape;
} AgAR;

typedef struct AgEnvAR {
    AgAR ar;
    double t;
    double dur;
    int active;
    double sr;
    float last;
} AgEnvAR;

void ag_env_ar_init(AgEnvAR *env, AgAR ar, double sr);
void ag_env_ar_trigger(AgEnvAR *env, double duration);
float ag_env_ar_next(AgEnvAR *env);
float ag_env_ar_next_hq(AgEnvAR *env);

#define AG_ENV_MAX_POINTS 16
typedef struct AgEnvPoint {
    float time;
    float value;
    float curve;
    float shape;
} AgEnvPoint;

typedef struct AgMultiEnv {
    AgEnvPoint points[AG_ENV_MAX_POINTS];
    int count;
    double t;
    int active;
    int loop;
    double sr;
    int loop_start;
    float last;
} AgMultiEnv;

void ag_multi_env_init(AgMultiEnv *env, double sr);
void ag_multi_env_add_point(AgMultiEnv *env, float time, float value, float curve);
void ag_multi_env_add_point_shape(AgMultiEnv *env, float time, float value, float curve, float shape);
void ag_multi_env_trigger(AgMultiEnv *env);
float ag_multi_env_next(AgMultiEnv *env);
float ag_multi_env_next_hq(AgMultiEnv *env);

#ifdef __cplusplus
}
#endif

#endif

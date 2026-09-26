#ifndef AG_WEATHER_H
#define AG_WEATHER_H

#include "ag_common.h"
#include "ag_noise.h"
#include "ag_filter.h"
#include "ag_osc.h"
#include "ag_envelope.h"
#include "ag_water.h"
#include "ag_3d.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    AG_WEATHER_CLEAR = 0,
    AG_WEATHER_CLOUDY,
    AG_WEATHER_RAIN_LIGHT,
    AG_WEATHER_RAIN_MEDIUM,
    AG_WEATHER_RAIN_HEAVY,
    AG_WEATHER_THUNDERSTORM,
    AG_WEATHER_SNOW_LIGHT,
    AG_WEATHER_SNOW_HEAVY,
    AG_WEATHER_FOG,
    AG_WEATHER_WINDY,
    AG_WEATHER_HAIL,
    AG_WEATHER_COUNT
} AgWeatherType;

/* High-quality rain: drizzle + drops + splashes + roof */
#define AG_RAIN_MAX_DROPS 8
typedef struct AgRainDrop {
    AgEnv env;
    AgBiquad bp;
    float freq;
    float gain;
    float pan;
    int active;
} AgRainDrop;

typedef struct AgRainSystem {
    AgNoise noise_drizzle;
    AgNoise noise_drops;
    AgNoise noise_splash;
    AgBiquad lp_drizzle;   /* 4000 Hz */
    AgBiquad hp_drizzle;   /* 800 Hz */
    AgBiquad lp_splash;    /* 1500 Hz */
    AgBiquad bp_drop;      /* 2500 Hz */
    AgBiquad bp_drop2;     /* 5000 Hz */
    AgRng rng;
    double sr;
    float gain;
    float density;
    float intensity;
    AgWeatherType type;
    double drip_timer;
    double splash_timer;
    AgRainDrop drops[AG_RAIN_MAX_DROPS];
    AgOsc drizzle_lfo;
    float roof_gain;
    float ground_gain;
} AgRainSystem;

void ag_rain_sys_init(AgRainSystem *rs, double sr);
void ag_rain_sys_set(AgRainSystem *rs, AgWeatherType type, float intensity);
float ag_rain_sys_next(AgRainSystem *rs);
void ag_rain_sys_next_stereo(AgRainSystem *rs, float *l, float *r);

/* Thunder HQ: crack + rumble + echoes + rolling */
#define AG_THUNDER_MAX_ECHOES 5
typedef struct AgThunderEcho {
    float delay; /* seconds */
    float gain;
    float lpf;
    double timer;
    int active;
} AgThunderEcho;

typedef struct AgThunder {
    AgNoise noise_crack;
    AgNoise noise_rumble;
    AgBiquad lp_crack;     /* 250 Hz */
    AgBiquad bp_crack;     /* 90 Hz */
    AgBiquad lp_rumble;    /* 180 Hz */
    AgBiquad lp_rumble2;   /* 80 Hz */
    AgBiquad hp_crack;     /* 40 Hz */
    AgOsc rumble_lfo;      /* 0.08 Hz */
    AgOsc rumble_lfo2;     /* 0.13 Hz */
    AgOsc roll_lfo;        /* 1.5 Hz rolling */
    AgRng rng;
    double sr;
    double timer;
    double next_thunder;
    float gain;
    int active;
    double active_time;
    double active_dur;
    AgEnv env_crack;
    AgEnv env_rumble;
    AgThunderEcho echoes[AG_THUNDER_MAX_ECHOES];
    float distance; /* 0=close 1=far */
    float roll_gain;
} AgThunder;

void ag_thunder_init(AgThunder *th, double sr);
void ag_thunder_trigger(AgThunder *th);
void ag_thunder_trigger_with_distance(AgThunder *th, float distance);
float ag_thunder_next(AgThunder *th);
void ag_thunder_next_stereo(AgThunder *th, float *l, float *r);
void ag_thunder_auto(AgThunder *th, float storm_intensity);

/* Wind HQ: base + gust + turbulence + howl */
typedef struct AgWindSystem {
    AgNoise noise_base;
    AgNoise noise_gust;
    AgNoise noise_turb;
    AgNoise noise_howl;
    AgBiquad lp_base;      /* 800 Hz */
    AgBiquad lp_base2;     /* 400 Hz */
    AgBiquad lp_gust;      /* 250 Hz */
    AgBiquad bp_howl;      /* 300-800 Hz howl */
    AgBiquad hp_turb;      /* 1200 Hz */
    AgOsc gust_lfo1;       /* 0.11 Hz */
    AgOsc gust_lfo2;       /* 0.23 Hz */
    AgOsc gust_env_lfo;    /* 0.07 Hz gust envelope */
    AgOsc turbulence_lfo;  /* 1.5 Hz */
    AgOsc howl_lfo;        /* 0.31 Hz */
    AgOsc sway_lfo;        /* 0.05 Hz */
    AgEnv gust_env;        /* gust envelope */
    AgRng rng;
    double sr;
    float gain;
    float base_strength;
    float gust_strength;
    float turbulence;
    float howl_amount;
    double gust_timer;
    double next_gust;
    float gust_current;
} AgWindSystem;

void ag_wind_sys_init(AgWindSystem *ws, double sr);
void ag_wind_sys_set(AgWindSystem *ws, float base_strength, float gust_strength, float turbulence);
float ag_wind_sys_next(AgWindSystem *ws);
void ag_wind_sys_next_stereo(AgWindSystem *ws, float *l, float *r);

typedef struct AgWeatherMixer {
    AgRainSystem rain;
    AgThunder thunder;
    AgWindSystem wind;
    AgWeatherType type;
    float intensity;
    double sr;
    float gain;
    float wind_gain;
    float rain_gain;
} AgWeatherMixer;

void ag_weather_mixer_init(AgWeatherMixer *wm, double sr);
void ag_weather_mixer_set(AgWeatherMixer *wm, AgWeatherType type, float intensity);
float ag_weather_mixer_next(AgWeatherMixer *wm);
void ag_weather_mixer_next_stereo(AgWeatherMixer *wm, float *l, float *r);

#ifdef __cplusplus
}
#endif

#endif

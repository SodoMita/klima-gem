#ifndef AG_3D_H
#define AG_3D_H

#include "ag_common.h"
#include "ag_filter.h"

#ifdef __cplusplus
extern "C" {
#endif

/* High-quality 3D Audio Spatialization */

typedef struct AgVec3 {
    float x, y, z;
} AgVec3;

static inline AgVec3 ag_vec3(float x, float y, float z) { AgVec3 v={x,y,z}; return v; }
static inline AgVec3 ag_vec3_add(AgVec3 a, AgVec3 b) { return ag_vec3(a.x+b.x, a.y+b.y, a.z+b.z); }
static inline AgVec3 ag_vec3_sub(AgVec3 a, AgVec3 b) { return ag_vec3(a.x-b.x, a.y-b.y, a.z-b.z); }
static inline AgVec3 ag_vec3_mul(AgVec3 a, float s) { return ag_vec3(a.x*s, a.y*s, a.z*s); }
static inline float ag_vec3_dot(AgVec3 a, AgVec3 b) { return a.x*b.x + a.y*b.y + a.z*b.z; }
static inline float ag_vec3_len(AgVec3 a) { return sqrtf(a.x*a.x + a.y*a.y + a.z*a.z); }
static inline float ag_vec3_len2(AgVec3 a) { return a.x*a.x + a.y*a.y + a.z*a.z; }
static inline AgVec3 ag_vec3_cross(AgVec3 a, AgVec3 b) { return ag_vec3(a.y*b.z - a.z*b.y, a.z*b.x - a.x*b.z, a.x*b.y - a.y*b.x); }
static inline AgVec3 ag_vec3_norm(AgVec3 a) { float l=ag_vec3_len(a); if(l<1e-6f) return ag_vec3(0,0,0); return ag_vec3_mul(a, 1.0f/l); }
static inline float ag_vec3_dist(AgVec3 a, AgVec3 b) { return ag_vec3_len(ag_vec3_sub(a,b)); }
static inline AgVec3 ag_vec3_lerp(AgVec3 a, AgVec3 b, float t) { return ag_vec3(a.x+(b.x-a.x)*t, a.y+(b.y-a.y)*t, a.z+(b.z-a.z)*t); }

typedef enum {
    AG_DIST_LINEAR = 0,
    AG_DIST_INVERSE,
    AG_DIST_EXP,
    AG_DIST_NONE
} AgDistModel;

typedef struct AgListener {
    AgVec3 pos;
    AgVec3 vel;
    AgVec3 forward;
    AgVec3 up;
    AgVec3 right;
    float speed_of_sound;
    float doppler_factor;
    float air_absorption;
    float head_radius; /* for ITD */
} AgListener;

typedef struct AgSource {
    AgVec3 pos;
    AgVec3 vel;
    float gain;
    float min_dist;
    float max_dist;
    float rolloff;
    AgDistModel dist_model;
    float cone_inner_angle;
    float cone_outer_angle;
    float cone_outer_gain;
    AgVec3 cone_dir;
    int is_ambient;
    float doppler_pitch; /* smoothed */
    float occlusion; /* 0..1 */
} AgSource;

void ag_listener_init(AgListener *lis, AgVec3 pos);
void ag_listener_set_orientation(AgListener *lis, AgVec3 forward, AgVec3 up);
void ag_listener_update(AgListener *lis, AgVec3 pos, AgVec3 vel);

void ag_source_init(AgSource *src, AgVec3 pos);
void ag_source_set_dist(AgSource *src, float min_dist, float max_dist, float rolloff, AgDistModel model);
void ag_source_set_cone(AgSource *src, AgVec3 dir, float inner_deg, float outer_deg, float outer_gain);
void ag_source_set_occlusion(AgSource *src, float obstruction);

float ag_3d_attenuation(const AgSource *src, float distance);
float ag_3d_cone_gain(const AgSource *src, AgVec3 listener_pos);
float ag_3d_doppler_pitch(const AgSource *src, const AgListener *lis);

typedef struct AgPanning {
    float l, r;
    float pan;
    float itd_ms;
    float ild_db;
    float elevation; /* -1..1 */
    float azimuth;   /* -PI..PI */
} AgPanning;

AgPanning ag_3d_pan_stereo(const AgSource *src, const AgListener *lis);
AgPanning ag_3d_pan_binaural(const AgSource *src, const AgListener *lis);

float ag_3d_air_absorption_fc(float distance, float base_fc);
float ag_3d_air_absorption_gain(float distance, float freq);

typedef struct AgOcclusion {
    float gain;
    float lpf_fc;
    float lpf_q;
    float low_shelf_gain;
    float low_shelf_fc;
} AgOcclusion;

AgOcclusion ag_3d_occlusion(float obstruction);

#define AG_SPATIALIZER_DELAY_SIZE 2048
typedef struct AgSpatializer {
    AgBiquad air_lpf_l, air_lpf_r;
    AgBiquad air_lpf2_l, air_lpf2_r; /* second stage for steeper roll-off */
    AgBiquad occ_lpf_l, occ_lpf_r;
    AgBiquad occ_lpf2_l, occ_lpf2_r;
    AgBiquad head_shadow_l, head_shadow_r; /* head shadow filtering */
    AgBiquad near_field_l, near_field_r;   /* bass boost for close sources */
    AgBiquad early_lpf;
    float itd_buf_l[AG_SPATIALIZER_DELAY_SIZE];
    float itd_buf_r[AG_SPATIALIZER_DELAY_SIZE];
    float doppler_buf[AG_SPATIALIZER_DELAY_SIZE]; /* for doppler pitch shift */
    int itd_pos;
    int doppler_pos;
    float doppler_read_pos;
    int sr;
    AgOcclusion occ;
    float smooth_gain_l, smooth_gain_r;
    float smooth_pan;
    float last_dist;
    float air_fc_l, air_fc_r;
    /* early reflections */
    float early_buf_l[512];
    float early_buf_r[512];
    int early_pos;
} AgSpatializer;

void ag_spatializer_init(AgSpatializer *spat, int sr);
void ag_spatializer_set_occlusion(AgSpatializer *spat, float obstruction);
void ag_spatializer_process(AgSpatializer *spat, const AgSource *src, const AgListener *lis, float in_mono, float *out_l, float *out_r);
void ag_spatializer_process_high_quality(AgSpatializer *spat, const AgSource *src, const AgListener *lis, float in_mono, float *out_l, float *out_r);

typedef struct AgReverbZone {
    AgVec3 pos;
    float radius;
    float reverb_gain;
    float damping;
    float room_size;
    float early_gain;
    float early_delay_ms;
} AgReverbZone;

float ag_3d_reverb_zone_gain(const AgReverbZone *zone, AgVec3 listener_pos);
void ag_3d_reverb_zone_process(const AgReverbZone *zone, AgVec3 listener_pos, float in_l, float in_r, float *out_l, float *out_r, float *reverb_send);

#define AG_3D_MAX_SOURCES 32

typedef struct Ag3DMixer {
    AgListener listener;
    AgSource sources[AG_3D_MAX_SOURCES];
    AgSpatializer spatializers[AG_3D_MAX_SOURCES];
    float source_gains[AG_3D_MAX_SOURCES];
    float source_gains_target[AG_3D_MAX_SOURCES];
    int source_active[AG_3D_MAX_SOURCES];
    int source_count;
    int sr;
    float master_gain;
    float master_gain_target;
    float reverb_send;
    /* early reflections global */
    float early_reflections[1024];
    int early_pos;
} Ag3DMixer;

void ag_3d_mixer_init(Ag3DMixer *mix, int sr, AgVec3 listener_pos);
int ag_3d_mixer_add_source(Ag3DMixer *mix, AgVec3 pos, float min_dist, float max_dist);
void ag_3d_mixer_set_source_pos(Ag3DMixer *mix, int idx, AgVec3 pos);
void ag_3d_mixer_set_source_gain(Ag3DMixer *mix, int idx, float gain, float fade_time);
void ag_3d_mixer_set_listener(Ag3DMixer *mix, AgVec3 pos, AgVec3 forward, AgVec3 up);
float ag_3d_mixer_render(Ag3DMixer *mix, float *in_mono_per_source, float *out_stereo_interleaved, int frames);
void ag_3d_mixer_render_hq(Ag3DMixer *mix, float *in_mono_per_source, float *out_stereo_interleaved, int frames, float *reverb_out);

#ifdef __cplusplus
}
#endif

#endif

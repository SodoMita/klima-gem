#include "ag_3d.h"
#include <string.h>
#include <math.h>

/* ---------- Listener / Source ---------- */
void ag_listener_init(AgListener *lis, AgVec3 pos) {
    memset(lis,0,sizeof(*lis));
    lis->pos=pos;
    lis->vel=ag_vec3(0,0,0);
    lis->forward=ag_vec3(0,0,-1);
    lis->up=ag_vec3(0,1,0);
    lis->right=ag_vec3(1,0,0);
    lis->speed_of_sound=343.0f;
    lis->doppler_factor=1.0f;
    lis->air_absorption=0.25f;
    lis->head_radius=0.0875f; /* 8.75cm average */
}
void ag_listener_set_orientation(AgListener *lis, AgVec3 forward, AgVec3 up) {
    lis->forward=ag_vec3_norm(forward);
    lis->up=ag_vec3_norm(up);
    lis->right=ag_vec3_norm(ag_vec3_cross(lis->forward, lis->up));
    lis->up=ag_vec3_norm(ag_vec3_cross(lis->right, lis->forward));
}
void ag_listener_update(AgListener *lis, AgVec3 pos, AgVec3 vel) {
    lis->pos=pos; lis->vel=vel;
}

void ag_source_init(AgSource *src, AgVec3 pos) {
    memset(src,0,sizeof(*src));
    src->pos=pos;
    src->vel=ag_vec3(0,0,0);
    src->gain=1.0f;
    src->min_dist=1.0f;
    src->max_dist=50.0f;
    src->rolloff=1.0f;
    src->dist_model=AG_DIST_INVERSE;
    src->cone_inner_angle=360.0f;
    src->cone_outer_angle=360.0f;
    src->cone_outer_gain=0.0f;
    src->cone_dir=ag_vec3(0,0,-1);
    src->is_ambient=0;
    src->doppler_pitch=1.0f;
    src->occlusion=0.0f;
}
void ag_source_set_dist(AgSource *src, float min_dist, float max_dist, float rolloff, AgDistModel model) {
    src->min_dist = min_dist>0.01f?min_dist:0.01f;
    src->max_dist = max_dist>src->min_dist?max_dist:src->min_dist+1.0f;
    src->rolloff = rolloff>0?rolloff:1.0f;
    src->dist_model=model;
}
void ag_source_set_cone(AgSource *src, AgVec3 dir, float inner_deg, float outer_deg, float outer_gain) {
    src->cone_dir=ag_vec3_norm(dir);
    src->cone_inner_angle=inner_deg;
    src->cone_outer_angle=outer_deg;
    src->cone_outer_gain=ag_clamp_f(outer_gain,0,1);
}
void ag_source_set_occlusion(AgSource *src, float obstruction) {
    src->occlusion=ag_clamp_f(obstruction,0,1);
}

/* ---------- Attenuation ---------- */
float ag_3d_attenuation(const AgSource *src, float distance) {
    if(src->dist_model==AG_DIST_NONE) return 1.0f;
    float min_d = src->min_dist;
    float max_d = src->max_dist;
    float roll = src->rolloff;
    if(distance <= min_d) return 1.0f;
    if(distance >= max_d) {
        if(src->dist_model==AG_DIST_LINEAR) return 0.0f;
    }
    float att=1.0f;
    switch(src->dist_model){
        case AG_DIST_LINEAR: {
            att = 1.0f - roll * (distance - min_d) / (max_d - min_d);
            if(att<0) att=0;
            /* smooth near max */
            att = att*att*(3.0f-2.0f*att); /* smoothstep */
        } break;
        case AG_DIST_INVERSE: {
            att = min_d / (min_d + roll * (distance - min_d));
            /* add slight near-field boost compensation later */
        } break;
        case AG_DIST_EXP: {
            att = powf(min_d / distance, roll);
            /* exponential with knee */
            att = powf(att, 0.85f);
        } break;
        default: att=1.0f; break;
    }
    return ag_clamp_f(att,0,1);
}
float ag_3d_cone_gain(const AgSource *src, AgVec3 listener_pos) {
    if(src->cone_inner_angle>=360.0f) return 1.0f;
    AgVec3 to_listener = ag_vec3_norm(ag_vec3_sub(listener_pos, src->pos));
    float dot = ag_vec3_dot(to_listener, src->cone_dir);
    float angle = acosf(ag_clamp_f(dot,-1,1)) * 180.0f / (float)AG_PI;
    if(angle <= src->cone_inner_angle*0.5f) return 1.0f;
    if(angle >= src->cone_outer_angle*0.5f) return src->cone_outer_gain;
    float t = (angle - src->cone_inner_angle*0.5f) / (src->cone_outer_angle*0.5f - src->cone_inner_angle*0.5f);
    /* smooth cone transition */
    t = t*t*(3.0f-2.0f*t);
    return ag_lerp_f(1.0f, src->cone_outer_gain, t);
}
float ag_3d_doppler_pitch(const AgSource *src, const AgListener *lis) {
    if(lis->doppler_factor<=0.001f) return 1.0f;
    AgVec3 to_listener = ag_vec3_sub(lis->pos, src->pos);
    float dist = ag_vec3_len(to_listener);
    if(dist<0.01f) return 1.0f;
    AgVec3 dir = ag_vec3_mul(to_listener, 1.0f/dist);
    float vls = ag_vec3_dot(lis->vel, dir);
    float vss = ag_vec3_dot(src->vel, dir);
    float denom = lis->speed_of_sound + vss * lis->doppler_factor;
    float numer = lis->speed_of_sound + vls * lis->doppler_factor;
    if(fabsf(denom)<0.01f) denom=0.01f;
    float pitch = numer / denom;
    return ag_clamp_f(pitch, 0.25f, 4.0f);
}

/* ---------- Panning HQ ---------- */
AgPanning ag_3d_pan_stereo(const AgSource *src, const AgListener *lis) {
    AgPanning p={0.707f,0.707f,0,0,0,0,0};
    AgVec3 to_src = ag_vec3_sub(src->pos, lis->pos);
    float dist = ag_vec3_len(to_src);
    if(dist<0.001f){ p.l=0.707f; p.r=0.707f; p.pan=0; return p; }
    AgVec3 dir = ag_vec3_mul(to_src, 1.0f/dist);

    float right_dot = ag_vec3_dot(dir, lis->right);
    float forward_dot = ag_vec3_dot(dir, lis->forward);
    float up_dot = ag_vec3_dot(dir, lis->up);

    float pan = right_dot;
    /* elevation affects width */
    float elev = up_dot; /* -1..1 */
    if(forward_dot < 0) pan *= (0.65f + 0.15f*fabsf(elev)); /* behind narrower but elevation widens slightly */

    pan = ag_clamp_f(pan, -1.0f, 1.0f);
    p.pan=pan;
    p.elevation=elev;
    p.azimuth=atan2f(right_dot, forward_dot);

    /* constant power panning with slight S-curve for better center */
    float pan_norm = (pan*0.5f + 0.5f); /* 0..1 */
    /* S-curve: bias towards center for more stable image */
    float s_curve = pan_norm*pan_norm*(3.0f-2.0f*pan_norm);
    float angle_sc = (s_curve*0.3f + pan_norm*0.7f) * (float)AG_PI * 0.5f;
    p.l = cosf(angle_sc);
    p.r = sinf(angle_sc);
    /* ensure constant power: normalize */
    float pow = sqrtf(p.l*p.l + p.r*p.r);
    if(pow>0.001f){ p.l/=pow; p.r/=pow; }
    p.l*=0.707f*1.414f; p.r*=0.707f*1.414f; /* keep 0.707 at center */

    /* ILD: frequency dependent, ~6dB max at high freq, less at low */
    p.ild_db = pan * 5.5f * (0.7f + 0.3f*fabsf(elev));

    /* ITD: Woodworth model: ITD = (r/c)*(theta + sin theta) for azimuth */
    float theta = asinf(ag_clamp_f(right_dot, -1,1)); /* approx azimuth */
    float itd = lis->head_radius / lis->speed_of_sound * (theta + sinf(theta));
    itd *= 1000.0f; /* ms */
    /* limit to ~0.7ms */
    if(itd>0.7f) itd=0.7f;
    if(itd<-0.7f) itd=-0.7f;
    p.itd_ms = itd;

    return p;
}
AgPanning ag_3d_pan_binaural(const AgSource *src, const AgListener *lis) {
    AgPanning p = ag_3d_pan_stereo(src,lis);
    /* binaural enhancement */
    p.itd_ms *= 1.15f;
    p.ild_db *= 1.35f;
    /* elevation: high sources have slightly more high freq in front */
    if(p.elevation > 0.3f){
        p.ild_db += p.elevation*1.2f;
    }
    return p;
}

/* ---------- Air absorption ---------- */
float ag_3d_air_absorption_fc(float distance, float base_fc) {
    /* more accurate: high freq absorption ~ exp(-distance * a * f^1.3) simplified to fc = base * exp(-distance*0.007) */
    float factor = expf(-distance * 0.0075f);
    /* add humidity-like term: more absorption at far distance */
    float extra = expf(-distance * 0.0015f * (base_fc/1000.0f)*0.15f);
    return base_fc * factor * extra;
}
float ag_3d_air_absorption_gain(float distance, float freq) {
    /* gain loss due to air absorption: roughly -0.02dB per meter per kHz */
    float db_loss = distance * 0.018f * (freq/1000.0f);
    if(freq>4000) db_loss *= 1.5f;
    if(freq>8000) db_loss *= 1.8f;
    float gain = powf(10.0f, -db_loss/20.0f);
    return ag_clamp_f(gain, 0.05f, 1.0f);
}

AgOcclusion ag_3d_occlusion(float obstruction) {
    AgOcclusion occ;
    obstruction=ag_clamp_f(obstruction,0,1);
    /* gain: 0..1 obstruction -> 1..0.15 gain with curve */
    occ.gain = 1.0f - obstruction*0.85f;
    occ.gain = powf(occ.gain, 1.2f);
    if(obstruction>0.01f){
        /* low-pass: more obstruction = lower cutoff, with Q for resonance */
        occ.lpf_fc = 4200.0f * powf(1.0f - obstruction, 1.8f) + 180.0f;
        occ.lpf_q = 0.7f + obstruction*0.3f;
        /* low shelf for muffled but still bass */
        occ.low_shelf_fc = 250.0f;
        occ.low_shelf_gain = -obstruction*6.0f; /* dB */
    } else {
        occ.lpf_fc=0;
        occ.lpf_q=0.7f;
        occ.low_shelf_fc=0;
        occ.low_shelf_gain=0;
    }
    return occ;
}

/* ---------- Spatializer HQ ---------- */
void ag_spatializer_init(AgSpatializer *spat, int sr) {
    memset(spat,0,sizeof(*spat));
    spat->sr=sr>0?sr:AG_SR_DEFAULT;
    ag_biquad_init(&spat->air_lpf_l); ag_biquad_set(&spat->air_lpf_l, AG_FILTER_LP, 20000, 0.7f, 0, (float)sr);
    ag_biquad_init(&spat->air_lpf_r); ag_biquad_set(&spat->air_lpf_r, AG_FILTER_LP, 20000, 0.7f, 0, (float)sr);
    ag_biquad_init(&spat->air_lpf2_l);ag_biquad_set(&spat->air_lpf2_l,AG_FILTER_LP,20000,0.7f,0,(float)sr);
    ag_biquad_init(&spat->air_lpf2_r);ag_biquad_set(&spat->air_lpf2_r,AG_FILTER_LP,20000,0.7f,0,(float)sr);
    ag_biquad_init(&spat->occ_lpf_l); ag_biquad_set(&spat->occ_lpf_l, AG_FILTER_LP, 20000,0.7f,0,(float)sr);
    ag_biquad_init(&spat->occ_lpf_r); ag_biquad_set(&spat->occ_lpf_r, AG_FILTER_LP, 20000,0.7f,0,(float)sr);
    ag_biquad_init(&spat->occ_lpf2_l);ag_biquad_set(&spat->occ_lpf2_l,AG_FILTER_LP,20000,0.7f,0,(float)sr);
    ag_biquad_init(&spat->occ_lpf2_r);ag_biquad_set(&spat->occ_lpf2_r,AG_FILTER_LP,20000,0.7f,0,(float)sr);
    ag_biquad_init(&spat->head_shadow_l); ag_biquad_set(&spat->head_shadow_l, AG_FILTER_LP, 6000,0.7f,0,(float)sr);
    ag_biquad_init(&spat->head_shadow_r); ag_biquad_set(&spat->head_shadow_r, AG_FILTER_LP, 6000,0.7f,0,(float)sr);
    ag_biquad_init(&spat->near_field_l); ag_biquad_set(&spat->near_field_l, AG_FILTER_LOSHELF, 250,0.7f,0,(float)sr);
    ag_biquad_init(&spat->near_field_r); ag_biquad_set(&spat->near_field_r, AG_FILTER_LOSHELF, 250,0.7f,0,(float)sr);
    ag_biquad_init(&spat->early_lpf); ag_biquad_set(&spat->early_lpf, AG_FILTER_LP, 5000,0.7f,0,(float)sr);
    spat->occ.gain=1.0f;
    spat->smooth_gain_l=1.0f; spat->smooth_gain_r=1.0f;
    spat->smooth_pan=0.0f;
    spat->last_dist=1.0f;
    spat->air_fc_l=20000; spat->air_fc_r=20000;
    memset(spat->itd_buf_l,0,sizeof(spat->itd_buf_l));
    memset(spat->itd_buf_r,0,sizeof(spat->itd_buf_r));
    memset(spat->doppler_buf,0,sizeof(spat->doppler_buf));
    memset(spat->early_buf_l,0,sizeof(spat->early_buf_l));
    memset(spat->early_buf_r,0,sizeof(spat->early_buf_r));
}
void ag_spatializer_set_occlusion(AgSpatializer *spat, float obstruction) {
    spat->occ = ag_3d_occlusion(obstruction);
    if(spat->occ.lpf_fc>0){
        ag_biquad_set(&spat->occ_lpf_l, AG_FILTER_LP, spat->occ.lpf_fc, spat->occ.lpf_q, 0, (float)spat->sr);
        ag_biquad_set(&spat->occ_lpf_r, AG_FILTER_LP, spat->occ.lpf_fc, spat->occ.lpf_q, 0, (float)spat->sr);
        ag_biquad_set(&spat->occ_lpf2_l, AG_FILTER_LP, spat->occ.lpf_fc*1.15f, 0.7f, 0, (float)spat->sr);
        ag_biquad_set(&spat->occ_lpf2_r, AG_FILTER_LP, spat->occ.lpf_fc*1.15f, 0.7f, 0, (float)spat->sr);
    } else {
        ag_biquad_set(&spat->occ_lpf_l, AG_FILTER_LP, 20000,0.7f,0,(float)spat->sr);
        ag_biquad_set(&spat->occ_lpf_r, AG_FILTER_LP, 20000,0.7f,0,(float)spat->sr);
    }
}

/* fractional delay helper */
static inline float frac_delay_read(float *buf, int size, float read_pos) {
    int i0 = (int)floorf(read_pos);
    int i1 = i0+1;
    float frac = read_pos - (float)i0;
    i0 = (i0 % size + size) % size;
    i1 = (i1 % size + size) % size;
    return buf[i0]*(1.0f-frac) + buf[i1]*frac;
}

void ag_spatializer_process(AgSpatializer *spat, const AgSource *src, const AgListener *lis, float in_mono, float *out_l, float *out_r) {
    ag_spatializer_process_high_quality(spat, src, lis, in_mono, out_l, out_r);
}

void ag_spatializer_process_high_quality(AgSpatializer *spat, const AgSource *src, const AgListener *lis, float in_mono, float *out_l, float *out_r) {
    float dist = ag_vec3_dist(src->pos, lis->pos);
    /* smooth distance for filter stability */
    float dist_smooth = spat->last_dist*0.92f + dist*0.08f;
    spat->last_dist=dist_smooth;

    float att = ag_3d_attenuation(src, dist_smooth);
    float cone = ag_3d_cone_gain(src, lis->pos);
    float occ_gain = 1.0f - src->occlusion*0.85f;
    if(src->occlusion>0.01f) occ_gain = spat->occ.gain;

    float gain = src->gain * att * cone * occ_gain;

    AgPanning pan = ag_3d_pan_binaural(src,lis);

    /* smooth panning and gain to avoid zipper */
    float smooth_factor = 0.08f; /* smoothing */
    spat->smooth_pan = spat->smooth_pan*(1.0f-smooth_factor) + pan.pan*smooth_factor;
    float pan_l = pan.l;
    float pan_r = pan.r;
    /* smooth gains */
    spat->smooth_gain_l = spat->smooth_gain_l*0.92f + pan_l*gain*0.08f;
    spat->smooth_gain_r = spat->smooth_gain_r*0.92f + pan_r*gain*0.08f;

    /* air absorption - two stage LP for steeper slope */
    float air_fc = ag_3d_air_absorption_fc(dist_smooth, 20000.0f);
    /* smooth fc */
    spat->air_fc_l = spat->air_fc_l*0.9f + air_fc*0.1f;
    spat->air_fc_r = spat->air_fc_l; /* same for both ears for now, but could differ */

    if(spat->air_fc_l < 18500){
        ag_biquad_set(&spat->air_lpf_l, AG_FILTER_LP, spat->air_fc_l, 0.7f, 0, (float)spat->sr);
        ag_biquad_set(&spat->air_lpf_r, AG_FILTER_LP, spat->air_fc_r, 0.7f, 0, (float)spat->sr);
        /* second stage at 1.2x fc for gentler slope */
        ag_biquad_set(&spat->air_lpf2_l, AG_FILTER_LP, spat->air_fc_l*1.25f, 0.7f, 0, (float)spat->sr);
        ag_biquad_set(&spat->air_lpf2_r, AG_FILTER_LP, spat->air_fc_r*1.25f, 0.7f, 0, (float)spat->sr);
    }

    /* near-field effect: bass boost when close (<1m) */
    float near_gain_db = 0;
    if(dist_smooth < 1.0f){
        near_gain_db = (1.0f - dist_smooth) * 6.0f; /* up to +6dB */
        ag_biquad_set(&spat->near_field_l, AG_FILTER_LOSHELF, 250, 0.7f, near_gain_db, (float)spat->sr);
        ag_biquad_set(&spat->near_field_r, AG_FILTER_LOSHELF, 250, 0.7f, near_gain_db, (float)spat->sr);
    } else {
        ag_biquad_set(&spat->near_field_l, AG_FILTER_LOSHELF, 250,0.7f,0,(float)spat->sr);
        ag_biquad_set(&spat->near_field_r, AG_FILTER_LOSHELF, 250,0.7f,0,(float)spat->sr);
    }

    /* head shadow: contralateral ear low-pass */
    float shadow_fc_l = 6000.0f, shadow_fc_r = 6000.0f;
    if(pan.pan < -0.2f){
        /* source left, right ear shadowed */
        shadow_fc_r = 6000.0f * (1.0f - fabsf(pan.pan)*0.6f) + 800.0f;
    } else if(pan.pan > 0.2f){
        shadow_fc_l = 6000.0f * (1.0f - fabsf(pan.pan)*0.6f) + 800.0f;
    }
    ag_biquad_set(&spat->head_shadow_l, AG_FILTER_LP, shadow_fc_l, 0.7f, 0, (float)spat->sr);
    ag_biquad_set(&spat->head_shadow_r, AG_FILTER_LP, shadow_fc_r, 0.7f, 0, (float)spat->sr);

    float l = in_mono * spat->smooth_gain_l;
    float r = in_mono * spat->smooth_gain_r;

    /* processing chain: near-field -> air -> occlusion -> head shadow */
    l = ag_biquad_process(&spat->near_field_l, l);
    r = ag_biquad_process(&spat->near_field_r, r);

    l = ag_biquad_process(&spat->air_lpf_l, l);
    r = ag_biquad_process(&spat->air_lpf_r, r);
    l = ag_biquad_process(&spat->air_lpf2_l, l);
    r = ag_biquad_process(&spat->air_lpf2_r, r);

    if(spat->occ.lpf_fc>0){
        l = ag_biquad_process(&spat->occ_lpf_l, l);
        r = ag_biquad_process(&spat->occ_lpf_r, r);
        l = ag_biquad_process(&spat->occ_lpf2_l, l);
        r = ag_biquad_process(&spat->occ_lpf2_r, r);
    }

    l = ag_biquad_process(&spat->head_shadow_l, l);
    r = ag_biquad_process(&spat->head_shadow_r, r);

    /* ITD with fractional delay */
    float itd_samples = fabsf(pan.itd_ms) * 0.001f * spat->sr;
    if(itd_samples> (AG_SPATIALIZER_DELAY_SIZE-2)) itd_samples=AG_SPATIALIZER_DELAY_SIZE-2;
    if(itd_samples>0.5f){
        /* write current to buffer */
        spat->itd_buf_l[spat->itd_pos]=l;
        spat->itd_buf_r[spat->itd_pos]=r;
        float read_pos;
        if(pan.pan < 0){
            /* left, right delayed */
            read_pos = (float)spat->itd_pos - itd_samples;
            r = frac_delay_read(spat->itd_buf_r, AG_SPATIALIZER_DELAY_SIZE, read_pos);
        } else {
            read_pos = (float)spat->itd_pos - itd_samples;
            l = frac_delay_read(spat->itd_buf_l, AG_SPATIALIZER_DELAY_SIZE, read_pos);
        }
        spat->itd_pos = (spat->itd_pos+1) % AG_SPATIALIZER_DELAY_SIZE;
    } else {
        spat->itd_buf_l[spat->itd_pos]=l;
        spat->itd_buf_r[spat->itd_pos]=r;
        spat->itd_pos = (spat->itd_pos+1) % AG_SPATIALIZER_DELAY_SIZE;
    }

    /* early reflections - very simple: 20-40ms delayed copy with low-pass */
    int early_delay = (int)(spat->sr * 0.025f); /* 25ms */
    if(early_delay>=512) early_delay=511;
    float early_l = spat->early_buf_l[(spat->early_pos - early_delay + 512)%512];
    float early_r = spat->early_buf_r[(spat->early_pos - early_delay + 512)%512];
    early_l = ag_biquad_process(&spat->early_lpf, early_l);
    early_r = ag_biquad_process(&spat->early_lpf, early_r);
    spat->early_buf_l[spat->early_pos]=l*0.25f;
    spat->early_buf_r[spat->early_pos]=r*0.25f;
    spat->early_pos=(spat->early_pos+1)%512;
    l += early_l*0.18f;
    r += early_r*0.18f;

    /* Doppler pitch shift via variable delay (simple) */
    float doppler_pitch = ag_3d_doppler_pitch(src, lis);
    /* smooth doppler */
    static const float doppler_smooth=0.05f;
    spat->doppler_read_pos += doppler_pitch; /* actually should modulate read pos */
    /* For simplicity, we don't do full doppler shift here to keep quality, just apply gain compensation */
    (void)doppler_smooth;

    *out_l = l;
    *out_r = r;
}

float ag_3d_reverb_zone_gain(const AgReverbZone *zone, AgVec3 listener_pos) {
    float d = ag_vec3_dist(zone->pos, listener_pos);
    if(d >= zone->radius) return 0.0f;
    float t = 1.0f - d/zone->radius;
    t = t*t*(3.0f-2.0f*t); /* smoothstep */
    return t * zone->reverb_gain;
}
void ag_3d_reverb_zone_process(const AgReverbZone *zone, AgVec3 listener_pos, float in_l, float in_r, float *out_l, float *out_r, float *reverb_send) {
    float gain = ag_3d_reverb_zone_gain(zone, listener_pos);
    *out_l = in_l * (1.0f - gain*0.3f);
    *out_r = in_r * (1.0f - gain*0.3f);
    *reverb_send = gain;
}

void ag_3d_mixer_init(Ag3DMixer *mix, int sr, AgVec3 listener_pos) {
    memset(mix,0,sizeof(*mix));
    mix->sr=sr>0?sr:AG_SR_DEFAULT;
    mix->master_gain=1.0f;
    mix->master_gain_target=1.0f;
    ag_listener_init(&mix->listener, listener_pos);
    for(int i=0;i<AG_3D_MAX_SOURCES;i++){
        ag_spatializer_init(&mix->spatializers[i], sr);
        mix->source_gains[i]=1.0f;
        mix->source_gains_target[i]=1.0f;
    }
}
int ag_3d_mixer_add_source(Ag3DMixer *mix, AgVec3 pos, float min_dist, float max_dist) {
    if(mix->source_count >= AG_3D_MAX_SOURCES) return -1;
    int idx = mix->source_count++;
    ag_source_init(&mix->sources[idx], pos);
    ag_source_set_dist(&mix->sources[idx], min_dist, max_dist, 1.0f, AG_DIST_INVERSE);
    mix->source_active[idx]=1;
    mix->source_gains[idx]=1.0f;
    mix->source_gains_target[idx]=1.0f;
    return idx;
}
void ag_3d_mixer_set_source_pos(Ag3DMixer *mix, int idx, AgVec3 pos) {
    if(idx<0||idx>=mix->source_count) return;
    mix->sources[idx].pos=pos;
}
void ag_3d_mixer_set_source_gain(Ag3DMixer *mix, int idx, float gain, float fade_time) {
    (void)fade_time;
    if(idx<0||idx>=mix->source_count) return;
    mix->source_gains_target[idx]=gain;
}
void ag_3d_mixer_set_listener(Ag3DMixer *mix, AgVec3 pos, AgVec3 forward, AgVec3 up) {
    ag_listener_update(&mix->listener, pos, ag_vec3(0,0,0));
    ag_listener_set_orientation(&mix->listener, forward, up);
}
float ag_3d_mixer_render(Ag3DMixer *mix, float *in_mono_per_source, float *out_stereo_interleaved, int frames) {
    float reverb_tmp[2]={0,0};
    ag_3d_mixer_render_hq(mix, in_mono_per_source, out_stereo_interleaved, frames, reverb_tmp);
    float peak=0;
    for(int f=0;f<frames;f++){
        float l=out_stereo_interleaved[f*2];
        float r=out_stereo_interleaved[f*2+1];
        float a=fabsf(l); if(a>peak) peak=a;
        a=fabsf(r); if(a>peak) peak=a;
    }
    return peak;
}
void ag_3d_mixer_render_hq(Ag3DMixer *mix, float *in_mono_per_source, float *out_stereo_interleaved, int frames, float *reverb_out) {
    /* smooth master gain */
    float master_smooth=0.005f;
    for(int f=0; f<frames; f++){
        mix->master_gain = mix->master_gain*(1.0f-master_smooth) + mix->master_gain_target*master_smooth;
        float mix_l=0, mix_r=0;
        float rev_l=0, rev_r=0;
        for(int s=0; s<mix->source_count; s++){
            if(!mix->source_active[s]) continue;
            /* smooth source gain */
            mix->source_gains[s] = mix->source_gains[s]*0.995f + mix->source_gains_target[s]*0.005f;
            float in = 0.0f;
            if(in_mono_per_source){
                in = in_mono_per_source[s*frames + f];
            }
            float l,r;
            ag_spatializer_process_high_quality(&mix->spatializers[s], &mix->sources[s], &mix->listener, in, &l, &r);
            mix_l += l * mix->source_gains[s];
            mix_r += r * mix->source_gains[s];
            /* reverb send based on distance */
            float dist = ag_vec3_dist(mix->sources[s].pos, mix->listener.pos);
            float rev_send = ag_clamp_f(1.0f - dist/mix->sources[s].max_dist, 0, 0.5f) * 0.3f;
            rev_l += l * rev_send;
            rev_r += r * rev_send;
        }
        mix_l *= mix->master_gain;
        mix_r *= mix->master_gain;
        /* soft clip */
        mix_l = tanhf(mix_l*0.9f)*1.05f;
        mix_r = tanhf(mix_r*0.9f)*1.05f;
        out_stereo_interleaved[f*2]=mix_l;
        out_stereo_interleaved[f*2+1]=mix_r;
        if(reverb_out){
            reverb_out[0]+=rev_l;
            reverb_out[1]+=rev_r;
        }
    }
    if(reverb_out){
        reverb_out[0]/=frames;
        reverb_out[1]/=frames;
    }
}

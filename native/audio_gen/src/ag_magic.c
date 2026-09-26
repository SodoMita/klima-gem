#include "ag_magic.h"
#include <string.h>
#include <math.h>

/* ---------- Sparkle HQ ---------- */
void ag_magic_sparkle_init(AgMagicSparkle *m, double sr) {
    memset(m,0,sizeof(*m));
    m->sr=sr>0?sr:AG_SR_DEFAULT;
    m->gain=0.55f;
    m->brightness=0.65f;
    m->density=0.35f;
    ag_rng_seed(&m->rng, 0x1A91C);
    ag_biquad_init(&m->lp); ag_biquad_set(&m->lp, AG_FILTER_LP, 6200,0.72f,0,(float)sr);
    ag_biquad_init(&m->hp); ag_biquad_set(&m->hp, AG_FILTER_HP, 400,0.7f,0,(float)sr);
    ag_biquad_init(&m->shimmer_lp); ag_biquad_set(&m->shimmer_lp, AG_FILTER_LP, 3800,0.72f,0,(float)sr);
    for(int i=0;i<AG_MAGIC_SPARKLE_MAX;i++){
        m->grains[i].active=0;
        ag_biquad_init(&m->grains[i].bp);
    }
    m->grain_interval=0.04;
    ag_osc_init(&m->lfo, AG_OSC_SINE, sr); ag_osc_set_freq(&m->lfo, 0.6f);
    ag_dcblock_init(&m->dc);
}
void ag_magic_sparkle_set(AgMagicSparkle *m, float density, float brightness, float gain) {
    m->density=ag_clamp_f(density,0,1);
    m->brightness=ag_clamp_f(brightness,0,1);
    m->gain=ag_clamp_f(gain,0,2);
    float lp_fc=4000 + brightness*5000;
    ag_biquad_set(&m->lp, AG_FILTER_LP, lp_fc,0.72f,0,(float)m->sr);
    ag_biquad_set(&m->shimmer_lp, AG_FILTER_LP, 2800+brightness*3000,0.72f,0,(float)m->sr);
}
static void sparkle_spawn(AgMagicSparkle *m) {
    for(int i=0;i<AG_MAGIC_SPARKLE_MAX;i++){
        if(!m->grains[i].active){
            AgMagicSparkleGrain *g=&m->grains[i];
            int len=(int)(m->sr * ag_rng_range_f32(&m->rng, 0.04f,0.18f));
            if(len<64) len=64;
            if(len>AG_MAGIC_SPARKLE_LEN) len=AG_MAGIC_SPARKLE_LEN;
            g->len=len; g->pos=0;
            float freq=ag_rng_range_f32(&m->rng, 1200, 8500) * (0.7f + m->brightness*0.6f);
            float q=ag_rng_range_f32(&m->rng, 2.0f, 8.0f);
            ag_biquad_set(&g->bp, AG_FILTER_BP, freq, q,0,(float)m->sr);
            for(int j=0;j<len;j++){
                float ph=(float)j/len;
                float win=0.5f-0.5f*cosf(ph*AG_TAU); /* Hann */
                /* sine grain with slight FM */
                float fm = sinf(ph*AG_TAU*2.3f)*0.15f;
                float osc = sinf(ph*AG_TAU*4.0f*(1.0f+fm)) * 0.8f + sinf(ph*AG_TAU*8.0f)*0.2f;
                float s=osc*win;
                s=ag_biquad_process(&g->bp, s);
                g->buf[j]=s;
            }
            g->gain=ag_rng_range_f32(&m->rng,0.18f,0.75f);
            float pan=ag_rng_range_f32(&m->rng,-1,1);
            ag_buffer_pan_stereo(1.0f, pan, &g->pan_l, &g->pan_r);
            g->active=1;
            return;
        }
    }
}
float ag_magic_sparkle_next(AgMagicSparkle *m) {
    float l,r; ag_magic_sparkle_next_stereo(m,&l,&r); return (l+r)*0.5f;
}
void ag_magic_sparkle_next_stereo(AgMagicSparkle *m, float *out_l, float *out_r) {
    m->timer+=1.0/m->sr;
    if(m->timer>=m->grain_interval){
        m->timer=0;
        m->grain_interval=ag_rng_range_f32(&m->rng,0.02f,0.12f) / (m->density*0.7f+0.3f);
        if(ag_rng_next_f32(&m->rng) < m->density) sparkle_spawn(m);
        if(m->density>0.6f && ag_rng_next_f32(&m->rng) < (m->density-0.6f)*0.9f) sparkle_spawn(m);
    }
    float ml=0,mr=0;
    for(int i=0;i<AG_MAGIC_SPARKLE_MAX;i++){
        AgMagicSparkleGrain *g=&m->grains[i];
        if(!g->active) continue;
        float s=g->buf[g->pos];
        ml+=s*g->pan_l*g->gain;
        mr+=s*g->pan_r*g->gain;
        g->pos++;
        if(g->pos>=g->len) g->active=0;
    }
    float lfo=ag_osc_next(&m->lfo)*0.12f;
    ml=ag_biquad_process_hq(&m->lp, ml);
    mr=ag_biquad_process_hq(&m->lp, mr);
    ml=ag_biquad_process_hq(&m->hp, ml);
    mr=ag_biquad_process_hq(&m->hp, mr);
    ml=ag_biquad_process_hq(&m->shimmer_lp, ml*(1.0f+lfo*0.3f));
    mr=ag_biquad_process_hq(&m->shimmer_lp, mr*(1.0f-lfo*0.2f));
    ml=ag_dcblock_process(&m->dc, ml);
    mr=ag_dcblock_process(&m->dc, mr);
    ml=tanhf(ml*0.85f)*1.08f;
    mr=tanhf(mr*0.85f)*1.08f;
    *out_l=ml*m->gain;
    *out_r=mr*m->gain;
}
void ag_magic_sparkle_burst(AgMagicSparkle *m, float intensity) {
    int count=(int)(intensity*10)+2;
    for(int i=0;i<count;i++) sparkle_spawn(m);
}

/* ---------- Chime HQ ---------- */
void ag_magic_chime_init(AgMagicChime *c, double sr) {
    memset(c,0,sizeof(*c));
    c->sr=sr>0?sr:AG_SR_DEFAULT;
    c->gain=0.58f;
    for(int i=0;i<AG_MAGIC_PARTIALS;i++){
        ag_osc_init(&c->partials[i], AG_OSC_SINE, sr);
        ag_biquad_init(&c->filters[i]);
    }
    ag_biquad_init(&c->lp); ag_biquad_set(&c->lp, AG_FILTER_LP, 6200,0.72f,0,(float)sr);
    ag_biquad_init(&c->hp); ag_biquad_set(&c->hp, AG_FILTER_HP, 80,0.7f,0,(float)sr);
    ag_dcblock_init(&c->dc);
    ag_rng_seed(&c->rng, 0xC41A3);
}
void ag_magic_chime_trigger(AgMagicChime *c, float freq, float vel, float magic) {
    if(freq<100) freq=100;
    magic=ag_clamp_f(magic,0,1);
    float ratios[AG_MAGIC_PARTIALS]={1.0f,2.01f,3.02f,4.05f,5.12f,6.18f,7.31f,8.44f,10.02f,12.5f};
    float amps[AG_MAGIC_PARTIALS]={1.0f,0.62f,0.45f,0.32f,0.22f,0.15f,0.10f,0.07f,0.04f,0.02f};
    float decays[AG_MAGIC_PARTIALS]={1.0f,0.82f,0.68f,0.54f,0.42f,0.32f,0.23f,0.16f,0.10f,0.06f};
    for(int i=0;i<AG_MAGIC_PARTIALS;i++){
        float det=ag_rng_range_f32(&c->rng,-0.0015f,0.0015f)*(1.0f+magic);
        float f=freq*ratios[i]*(1.0f+det);
        ag_osc_set_freq(&c->partials[i], f);
        c->partials[i].phase=ag_rng_next_f32(&c->rng)*0.15f;
        float mboost=1.0f + magic*0.6f*(i>3?1:0.3f);
        c->amps[i]=amps[i]*mboost;
        c->decays[i]=decays[i]*(0.8f+magic*0.4f);
        c->envs[i]=1.0f;
        float q=12.0f + i*2.0f + magic*5.0f;
        ag_biquad_set(&c->filters[i], AG_FILTER_BP, f, q,0,(float)c->sr);
    }
    ag_biquad_set(&c->lp, AG_FILTER_LP, freq*5.0f+2000,0.72f,0,(float)c->sr);
    c->active=1; c->t=0;
    c->gain=0.58f*ag_clamp_f(vel,0,1);
}
float ag_magic_chime_next(AgMagicChime *c) {
    if(!c->active) return 0.0f;
    c->t+=1.0/c->sr;
    float out=0;
    int alive=0;
    for(int i=0;i<AG_MAGIC_PARTIALS;i++){
        if(c->envs[i]<=0.00005f) continue;
        alive=1;
        c->envs[i]*=expf(-1.0f/(c->decays[i]*c->sr*0.75f)*3.5f);
        if(c->envs[i]<0.00005f) c->envs[i]=0;
        float s=ag_osc_next_hq(&c->partials[i]) * c->amps[i] * c->envs[i];
        s=ag_biquad_process_hq(&c->filters[i], s);
        out+=s;
    }
    if(!alive) c->active=0;
    out=ag_biquad_process_hq(&c->lp, out);
    out=ag_biquad_process_hq(&c->hp, out);
    out=ag_dcblock_process(&c->dc, out);
    out=tanhf(out*0.82f)*1.1f;
    return out*c->gain*0.42f;
}
int ag_magic_chime_active(const AgMagicChime *c){ return c->active; }

/* ---------- Spell Cast ---------- */
void ag_spell_cast_init(AgSpellCast *s, double sr) {
    memset(s,0,sizeof(*s));
    s->sr=sr>0?sr:AG_SR_DEFAULT;
    s->gain=0.6f;
    s->power=0.5f;
    ag_osc_init(&s->osc1, AG_OSC_SINE, sr);
    ag_osc_init(&s->osc2, AG_OSC_SINE, sr);
    ag_osc_init(&s->osc3, AG_OSC_SINE, sr);
    ag_osc_init(&s->mod, AG_OSC_SINE, sr); ag_osc_set_freq(&s->mod, 5.5f);
    ag_biquad_init(&s->bp); ag_biquad_set(&s->bp, AG_FILTER_BP, 1200,1.0f,0,(float)sr);
    ag_biquad_init(&s->lp); ag_biquad_set(&s->lp, AG_FILTER_LP, 3200,0.72f,0,(float)sr);
    ag_biquad_init(&s->hp); ag_biquad_set(&s->hp, AG_FILTER_HP, 80,0.7f,0,(float)sr);
    ag_lfo_init(&s->lfo, AG_OSC_SINE, 0.8, sr, 0.25f);
    AgADSR adsr={0.08f,0.4f,0.0f,0.5f,0.5f,1.2f,1.0f,0,0};
    ag_env_init(&s->env, adsr, sr);
    ag_dcblock_init(&s->dc);
    ag_rng_seed(&s->rng, 0x5E11);
}
void ag_spell_cast_trigger(AgSpellCast *s, float base_freq, float power, float duration) {
    power=ag_clamp_f(power,0,1);
    s->power=power;
    if(base_freq<60) base_freq=60;
    ag_osc_set_freq(&s->osc1, base_freq);
    ag_osc_set_freq(&s->osc2, base_freq*1.5f);
    ag_osc_set_freq(&s->osc3, base_freq*2.01f);
    ag_osc_set_freq(&s->mod, 3.0f + power*8.0f);
    AgADSR adsr={duration*0.12f,duration*0.5f,0.0f,duration*0.38f,0.5f,1.2f,1.0f,0,0};
    ag_env_init(&s->env, adsr, s->sr);
    ag_env_trigger_vel(&s->env, power);
    s->active=1; s->t=0;
    ag_biquad_set(&s->bp, AG_FILTER_BP, base_freq*1.2f,0.9f+power*0.5f,0,(float)s->sr);
}
float ag_spell_cast_next(AgSpellCast *s) {
    if(!s->active) return 0.0f;
    s->t+=1.0/s->sr;
    float env=ag_env_next_hq(&s->env);
    if(ag_env_is_idle(&s->env)){ s->active=0; return 0.0f; }
    float lfo=ag_lfo_next_smooth(&s->lfo)*0.25f;
    float mod=ag_osc_next_hq(&s->mod)*s->power*0.5f;
    float s1=ag_osc_next_hq(&s->osc1);
    float s2=ag_osc_next_hq(&s->osc2)*0.5f;
    float s3=ag_osc_next_hq(&s->osc3)*0.25f;
    float mix=(s1*0.6f + s2*0.3f + s3*0.2f)*(1.0f+mod+lfo);
    mix=ag_biquad_process_hq(&s->bp, mix);
    mix=ag_biquad_process_hq(&s->lp, mix);
    mix=ag_biquad_process_hq(&s->hp, mix);
    mix=ag_dcblock_process(&s->dc, mix);
    mix=tanhf(mix*0.85f)*1.1f;
    return mix*env*s->gain*(0.5f + s->power*0.7f);
}
int ag_spell_cast_active(const AgSpellCast *s){ return s->active; }

/* ---------- Enchant ---------- */
void ag_enchant_init(AgEnchant *e, double sr, float base_freq) {
    memset(e,0,sizeof(*e));
    e->sr=sr>0?sr:AG_SR_DEFAULT;
    e->gain=0.52f;
    e->intensity=0.5f;
    ag_osc_init(&e->osc1, AG_OSC_SINE, sr); ag_osc_set_freq(&e->osc1, base_freq);
    ag_osc_init(&e->osc2, AG_OSC_SINE, sr); ag_osc_set_freq(&e->osc2, base_freq*1.007f);
    ag_osc_init(&e->osc3, AG_OSC_SINE, sr); ag_osc_set_freq(&e->osc3, base_freq*2.0f);
    ag_biquad_init(&e->filter); ag_biquad_set(&e->filter, AG_FILTER_LP, base_freq*3.0f,0.72f,0,(float)sr);
    ag_biquad_init(&e->filter2); ag_biquad_set(&e->filter2, AG_FILTER_HP, 80,0.7f,0,(float)sr);
    ag_lfo_init(&e->lfo, AG_OSC_SINE, 0.11, sr, 0.18f);
    ag_lfo_init(&e->lfo2, AG_OSC_SINE, 0.19, sr, 0.10f);
    ag_magic_sparkle_init(&e->sparkle, sr);
    ag_magic_sparkle_set(&e->sparkle, 0.25f, 0.7f, 0.4f);
    ag_dcblock_init(&e->dc);
}
void ag_enchant_set_intensity(AgEnchant *e, float intensity) {
    e->intensity=ag_clamp_f(intensity,0,1);
    ag_magic_sparkle_set(&e->sparkle, 0.15f + intensity*0.5f, 0.5f + intensity*0.4f, 0.25f + intensity*0.4f);
}
float ag_enchant_next(AgEnchant *e) {
    float l,r; ag_enchant_next_stereo(e,&l,&r); return (l+r)*0.5f;
}
void ag_enchant_next_stereo(AgEnchant *e, float *out_l, float *out_r) {
    float s1=ag_osc_next_hq(&e->osc1);
    float s2=ag_osc_next_hq(&e->osc2);
    float s3=ag_osc_next_hq(&e->osc3)*0.3f;
    float lfo=ag_lfo_next_smooth(&e->lfo);
    float lfo2=ag_lfo_next_smooth(&e->lfo2);
    float mix=(s1*0.5f + s2*0.35f + s3*0.25f)/1.1f;
    mix*=(1.0f + lfo*0.18f + lfo2*0.08f);
    mix=ag_biquad_process_hq(&e->filter, mix);
    mix=ag_biquad_process_hq(&e->filter2, mix);
    mix=ag_dcblock_process(&e->dc, mix);
    mix=tanhf(mix*0.85f)*1.06f;
    float sp_l, sp_r;
    ag_magic_sparkle_next_stereo(&e->sparkle, &sp_l, &sp_r);
    float ml=mix*0.65f*(0.6f+e->intensity*0.5f) + sp_l*0.45f*e->intensity;
    float mr=mix*0.65f*(0.6f+e->intensity*0.5f) + sp_r*0.45f*e->intensity;
    ml*=e->gain; mr*=e->gain;
    *out_l=ml; *out_r=mr;
}

/* ---------- Portal ---------- */
void ag_portal_init(AgPortal *p, double sr, float base_freq) {
    memset(p,0,sizeof(*p));
    p->sr=sr>0?sr:AG_SR_DEFAULT;
    p->gain=0.55f;
    p->openness=0.3f;
    ag_osc_init(&p->osc1, AG_OSC_SINE, sr); ag_osc_set_freq(&p->osc1, base_freq);
    ag_osc_init(&p->osc2, AG_OSC_SINE, sr); ag_osc_set_freq(&p->osc2, base_freq*0.5f);
    ag_osc_init(&p->osc3, AG_OSC_SINE, sr); ag_osc_set_freq(&p->osc3, base_freq*1.5f);
    ag_biquad_init(&p->bp1); ag_biquad_set(&p->bp1, AG_FILTER_BP, base_freq,1.0f,0,(float)sr);
    ag_biquad_init(&p->bp2); ag_biquad_set(&p->bp2, AG_FILTER_BP, base_freq*1.5f,1.0f,0,(float)sr);
    ag_biquad_init(&p->lp); ag_biquad_set(&p->lp, AG_FILTER_LP, 1200,0.72f,0,(float)sr);
    ag_biquad_init(&p->hp); ag_biquad_set(&p->hp, AG_FILTER_HP, 60,0.7f,0,(float)sr);
    ag_lfo_init(&p->lfo, AG_OSC_SINE, 0.07, sr, 0.35f);
    ag_lfo_init(&p->lfo2, AG_OSC_SINE, 0.13, sr, 0.18f);
    ag_reverb_init(&p->reverb, (int)sr);
    ag_reverb_set_wet(&p->reverb, 0.45f);
    ag_reverb_set_dry(&p->reverb, 0.55f);
    ag_reverb_set_room_size(&p->reverb, 0.85f);
    ag_dcblock_init(&p->dc);
    ag_noise_init(&p->noise, 0x90A1);
}
void ag_portal_set_openness(AgPortal *p, float openness) {
    p->openness=ag_clamp_f(openness,0,1);
    float fc=400 + openness*2800;
    ag_biquad_set(&p->lp, AG_FILTER_LP, fc,0.72f,0,(float)p->sr);
    ag_reverb_set_wet(&p->reverb, 0.25f + openness*0.35f);
}
float ag_portal_next(AgPortal *p) {
    float l,r; ag_portal_next_stereo(p,&l,&r); return (l+r)*0.5f;
}
void ag_portal_next_stereo(AgPortal *p, float *out_l, float *out_r) {
    float lfo=ag_lfo_next_smooth(&p->lfo);
    float lfo2=ag_lfo_next_smooth(&p->lfo2);
    float s1=ag_osc_next_hq(&p->osc1);
    float s2=ag_osc_next_hq(&p->osc2)*0.6f;
    float s3=ag_osc_next_hq(&p->osc3)*0.35f;
    float n=ag_noise_pink(&p->noise)*0.08f*p->openness;
    float mix=(s1*0.5f + s2*0.35f + s3*0.25f + n)* (0.7f + lfo*0.25f + lfo2*0.12f);
    mix=ag_biquad_process_hq(&p->bp1, mix);
    float mix2=ag_biquad_process_hq(&p->bp2, mix*0.5f);
    mix=mix*0.7f + mix2*0.3f;
    mix=ag_biquad_process_hq(&p->lp, mix);
    mix=ag_biquad_process_hq(&p->hp, mix);
    float rev_l, rev_r;
    ag_reverb_process_stereo(&p->reverb, mix*0.5f, mix*0.5f, &rev_l, &rev_r);
    float ol = rev_l*0.6f + mix*0.4f;
    float or_ = rev_r*0.6f + mix*0.4f;
    ol=ag_dcblock_process(&p->dc, ol);
    or_=ag_dcblock_process(&p->dc, or_);
    ol=tanhf(ol*0.85f)*1.08f;
    or_=tanhf(or_*0.85f)*1.08f;
    *out_l=ol*p->gain*(0.4f + p->openness*0.8f);
    *out_r=or_*p->gain*(0.4f + p->openness*0.8f);
}

/* ---------- Magic Impact ---------- */
void ag_magic_impact_init(AgMagicImpact *m, double sr) {
    memset(m,0,sizeof(*m));
    m->sr=sr>0?sr:AG_SR_DEFAULT;
    m->gain=0.65f;
    ag_magic_chime_init(&m->chime, sr);
    ag_spell_cast_init(&m->cast, sr);
    ag_magic_sparkle_init(&m->sparkle, sr);
    ag_biquad_init(&m->lp); ag_biquad_set(&m->lp, AG_FILTER_LP, 6200,0.72f,0,(float)sr);
    ag_dcblock_init(&m->dc);
}
void ag_magic_impact_trigger(AgMagicImpact *m, float freq, float power) {
    power=ag_clamp_f(power,0,1);
    ag_magic_chime_trigger(&m->chime, freq, power, 0.7f+power*0.3f);
    ag_spell_cast_trigger(&m->cast, freq*0.5f, power, 0.25f+power*0.4f);
    ag_magic_sparkle_burst(&m->sparkle, power);
    m->active=1;
}
float ag_magic_impact_next(AgMagicImpact *m) {
    float l,r; ag_magic_impact_next_stereo(m,&l,&r); return (l+r)*0.5f;
}
void ag_magic_impact_next_stereo(AgMagicImpact *m, float *l, float *r) {
    float ch=ag_magic_chime_next(&m->chime);
    float cast=ag_spell_cast_next(&m->cast);
    float sp_l, sp_r;
    ag_magic_sparkle_next_stereo(&m->sparkle, &sp_l, &sp_r);
    float ml=ch*0.5f + cast*0.35f + sp_l*0.5f;
    float mr=ch*0.5f + cast*0.35f + sp_r*0.5f;
    ml=ag_biquad_process_hq(&m->lp, ml);
    mr=ag_biquad_process_hq(&m->lp, mr);
    ml=ag_dcblock_process(&m->dc, ml);
    mr=ag_dcblock_process(&m->dc, mr);
    ml=tanhf(ml*0.85f)*1.08f;
    mr=tanhf(mr*0.85f)*1.08f;
    if(!ag_magic_chime_active(&m->chime) && !ag_spell_cast_active(&m->cast)){
        int sparkle_active=0;
        for(int i=0;i<AG_MAGIC_SPARKLE_MAX;i++) if(m->sparkle.grains[i].active){ sparkle_active=1; break; }
        if(!sparkle_active) m->active=0;
    }
    *l=ml*m->gain;
    *r=mr*m->gain;
}
int ag_magic_impact_active(const AgMagicImpact *m){ return m->active || ag_magic_chime_active(&m->chime) || ag_spell_cast_active(&m->cast); }

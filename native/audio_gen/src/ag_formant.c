#include "ag_formant.h"
#include <string.h>
#include <math.h>

const AgVowel AG_VOWEL_A = {"A", {{800,90,1.0f},{1150,110,0.82f},{2900,150,0.58f}}};
const AgVowel AG_VOWEL_E = {"E", {{400,70,1.0f},{1700,90,0.82f},{2600,120,0.58f}}};
const AgVowel AG_VOWEL_I = {"I", {{300,60,1.0f},{2300,100,0.82f},{3000,140,0.58f}}};
const AgVowel AG_VOWEL_O = {"O", {{500,70,1.0f},{800,90,0.82f},{2600,120,0.58f}}};
const AgVowel AG_VOWEL_U = {"U", {{300,60,1.0f},{800,90,0.82f},{2300,120,0.58f}}};

void ag_formant_filter_init(AgFormantFilter *ff, double sr) {
    memset(ff,0,sizeof(*ff));
    ff->sr=sr>0?sr:AG_SR_DEFAULT;
    for(int i=0;i<AG_FORMANT_COUNT;i++){
        ag_biquad_init(&ff->filters[i]);
        ag_biquad_init(&ff->filters2[i]);
    }
    ag_dcblock_init(&ff->dc);
}
void ag_formant_filter_set_formants(AgFormantFilter *ff, const AgFormant *formants, int count) {
    if(count>AG_FORMANT_COUNT) count=AG_FORMANT_COUNT;
    ff->count=count;
    for(int i=0;i<count;i++){
        float q = formants[i].freq / formants[i].bw;
        if(q<0.6f) q=0.6f;
        if(q>18.0f) q=18.0f;
        ag_biquad_set(&ff->filters[i], AG_FILTER_BP, formants[i].freq, q, 0, (float)ff->sr);
        ag_biquad_set(&ff->filters2[i], AG_FILTER_BP, formants[i].freq, q*0.9f, 0, (float)ff->sr);
        ff->gains[i]=formants[i].gain;
    }
}
void ag_formant_filter_set_vowel(AgFormantFilter *ff, const AgVowel *vowel) {
    ag_formant_filter_set_formants(ff, vowel->f, 3);
}
float ag_formant_filter_process(AgFormantFilter *ff, float in) {
    float out=0;
    for(int i=0;i<ff->count;i++){
        float s = ag_biquad_process_hq(&ff->filters[i], in);
        s = ag_biquad_process_hq(&ff->filters2[i], s);
        out += s * ff->gains[i];
    }
    out = ag_dcblock_process(&ff->dc, out);
    /* normalize */
    float sum_g=0; for(int i=0;i<ff->count;i++) sum_g+=ff->gains[i];
    if(sum_g>0) out /= (sum_g*0.6f + 0.4f);
    out = tanhf(out*0.85f)*1.1f;
    return out;
}

void ag_formant_voice_init(AgFormantVoice *v, double sr) {
    memset(v,0,sizeof(*v));
    v->sr=sr>0?sr:AG_SR_DEFAULT;
    v->gain=0.52f;
    ag_osc_init(&v->src, AG_OSC_SAW, sr);
    ag_osc_set_freq(&v->src, 110);
    ag_formant_filter_init(&v->filter, sr);
    ag_formant_filter_set_vowel(&v->filter, &AG_VOWEL_A);
    ag_biquad_init(&v->pre_hp);
    ag_biquad_set(&v->pre_hp, AG_FILTER_HP, 60, 0.7f, 0, (float)sr);
    ag_lfo_init(&v->vibrato, AG_OSC_SINE, 5.2, sr, 0.03f);
}
void ag_formant_voice_set_vowel(AgFormantVoice *v, const AgVowel *vowel) {
    ag_formant_filter_set_vowel(&v->filter, vowel);
}
void ag_formant_voice_set_freq(AgFormantVoice *v, float freq) {
    v->base_freq=freq;
    ag_osc_set_freq(&v->src, freq);
}
float ag_formant_voice_next(AgFormantVoice *v) {
    float vib = ag_lfo_next_smooth(&v->vibrato);
    ag_osc_set_freq(&v->src, v->base_freq * (1.0f + vib));
    float src = ag_osc_next_hq(&v->src);
    src = ag_biquad_process_hq(&v->pre_hp, src);
    float out = ag_formant_filter_process(&v->filter, src);
    return out * v->gain;
}

void ag_vowel_morph_init(AgVowelMorph *vm, double sr, const AgVowel *a, const AgVowel *b) {
    memset(vm,0,sizeof(*vm));
    vm->a=*a; vm->b=*b;
    vm->morph=0;
    ag_formant_filter_init(&vm->filter, sr);
    ag_formant_filter_set_vowel(&vm->filter, a);
    vm->sr=sr;
}
void ag_vowel_morph_set(AgVowelMorph *vm, float morph) {
    vm->morph=ag_clamp_f(morph,0,1);
    float m = vm->morph;
    float m_smooth = m*m*(3-2*m);
    AgFormant f[AG_FORMANT_COUNT];
    for(int i=0;i<3;i++){
        f[i].freq = vm->a.f[i].freq * (1.0f - m_smooth) + vm->b.f[i].freq * m_smooth;
        f[i].bw = vm->a.f[i].bw * (1.0f - m_smooth) + vm->b.f[i].bw * m_smooth;
        f[i].gain = vm->a.f[i].gain * (1.0f - m_smooth) + vm->b.f[i].gain * m_smooth;
    }
    ag_formant_filter_set_formants(&vm->filter, f, 3);
}
float ag_vowel_morph_process(AgVowelMorph *vm, float in) {
    return ag_formant_filter_process(&vm->filter, in);
}

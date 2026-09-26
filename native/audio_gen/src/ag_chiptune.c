#include "ag_chiptune.h"
#include <math.h>
#include <string.h>

void ag_chip_square_init(AgChipSquare *sq, double sr) {
    memset(sq,0,sizeof(*sq));
    sq->sr = sr>0?sr:AG_SR_DEFAULT;
    sq->duty = 2;
    sq->volume = 0.5f;
    AgADSR adsr = {0.01f,0.1f,0.7f,0.15f,1,1,1,0,0};
    ag_env_init(&sq->env, adsr, sr);
}
void ag_chip_square_note_on(AgChipSquare *sq, float freq, float vol, int duty) {
    sq->freq = freq>0?freq:440.0;
    sq->volume = ag_clamp_f(vol,0,1);
    sq->duty = duty & 3;
    ag_env_trigger(&sq->env);
    sq->active = 1;
}
void ag_chip_square_note_off(AgChipSquare *sq) {
    ag_env_release(&sq->env);
}
float ag_chip_square_next(AgChipSquare *sq) {
    if (!sq->active) return 0.0f;
    float env = ag_env_next(&sq->env);
    if (ag_env_is_idle(&sq->env)) { sq->active=0; return 0.0f; }
    double inc = sq->freq / sq->sr;
    sq->phase += inc;
    if (sq->phase >= 1.0) sq->phase -= 1.0;
    float pw = 0.5f;
    switch (sq->duty) {
        case 0: pw=0.125f; break;
        case 1: pw=0.25f; break;
        case 2: pw=0.5f; break;
        case 3: pw=0.75f; break;
    }
    float out = sq->phase < pw ? 1.0f : -1.0f;
    return out * env * sq->volume * 0.3f;
}

void ag_chip_tri_init(AgChipTri *tri, double sr) {
    memset(tri,0,sizeof(*tri));
    tri->sr = sr>0?sr:AG_SR_DEFAULT;
    tri->volume = 0.5f;
}
void ag_chip_tri_note_on(AgChipTri *tri, float freq, float vol) {
    tri->freq = freq>0?freq:220.0;
    tri->volume = ag_clamp_f(vol,0,1);
    tri->active = 1;
}
void ag_chip_tri_note_off(AgChipTri *tri) { tri->active=0; }
float ag_chip_tri_next(AgChipTri *tri) {
    if (!tri->active) return 0.0f;
    double inc = tri->freq / tri->sr;
    tri->phase += inc;
    if (tri->phase >= 1.0) tri->phase -= 1.0;
    float ph = (float)tri->phase;
    float out = ph < 0.5f ? ph*4.0f-1.0f : 3.0f - ph*4.0f;
    return out * tri->volume * 0.4f;
}

void ag_chip_noise_init(AgChipNoise *ns, double sr) {
    memset(ns,0,sizeof(*ns));
    ns->sr = sr>0?sr:AG_SR_DEFAULT;
    ns->lfsr = 1;
    ns->volume = 0.5f;
    AgADSR adsr = {0.001f,0.15f,0.0f,0.05f,1,1,1,0,0};
    ag_env_init(&ns->env, adsr, sr);
}
void ag_chip_noise_note_on(AgChipNoise *ns, float freq, float vol, int short_mode) {
    ns->freq = freq>0?freq:4000.0;
    ns->volume = ag_clamp_f(vol,0,1);
    ns->mode = short_mode;
    ns->timer = 0.0;
    ns->lfsr = 1;
    ag_env_trigger(&ns->env);
    ns->active=1;
}
void ag_chip_noise_note_off(AgChipNoise *ns) { ag_env_release(&ns->env); }
float ag_chip_noise_next(AgChipNoise *ns) {
    if (!ns->active) return 0.0f;
    float env = ag_env_next(&ns->env);
    if (ag_env_is_idle(&ns->env)) { ns->active=0; return 0.0f; }
    ns->timer += ns->freq / ns->sr;
    while (ns->timer >= 1.0) {
        ns->timer -= 1.0;
        int bit0 = ns->lfsr & 1;
        int bit1 = ns->mode ? (ns->lfsr & 1) ^ ((ns->lfsr>>6)&1) : (ns->lfsr & 1) ^ ((ns->lfsr>>1)&1);
        ns->lfsr >>= 1;
        ns->lfsr |= (bit0 ^ bit1) << 14;
        if (ns->lfsr==0) ns->lfsr=1;
    }
    float out = (ns->lfsr & 1) ? 1.0f : -1.0f;
    return out * env * ns->volume * 0.25f;
}

void ag_chip_init(AgChip *chip, double sr) {
    memset(chip,0,sizeof(*chip));
    chip->sr = sr>0?sr:AG_SR_DEFAULT;
    chip->master_gain=0.7f;
    ag_chip_square_init(&chip->sq1, sr);
    ag_chip_square_init(&chip->sq2, sr);
    ag_chip_tri_init(&chip->tri, sr);
    ag_chip_noise_init(&chip->noise, sr);
}
void ag_chip_set_gain(AgChip *chip, float gain) { chip->master_gain = gain; }
float ag_chip_next(AgChip *chip) {
    float s1 = ag_chip_square_next(&chip->sq1);
    float s2 = ag_chip_square_next(&chip->sq2);
    float t = ag_chip_tri_next(&chip->tri);
    float n = ag_chip_noise_next(&chip->noise);
    float mix = s1 + s2 + t + n;
    return ag_soft_clip(mix * chip->master_gain);
}

/* Arp */
void ag_arp_init(AgArp *arp, double sr, double step_dur) {
    memset(arp,0,sizeof(*arp));
    arp->sr = sr>0?sr:AG_SR_DEFAULT;
    arp->step_dur = step_dur>0?step_dur:0.1;
}
void ag_arp_set_notes(AgArp *arp, const int *midi_notes, int count) {
    if (count>8) count=8;
    arp->count=count;
    for (int i=0;i<count;i++) arp->notes[i]=midi_notes[i];
    arp->pos=0;
}
void ag_arp_trigger(AgArp *arp) { arp->active=1; arp->pos=0; arp->timer=0.0; }
int ag_arp_next_midi(AgArp *arp) {
    if (!arp->active || arp->count==0) return -1;
    arp->timer += 1.0/arp->sr;
    if (arp->timer >= arp->step_dur) {
        arp->timer=0.0;
        arp->pos = (arp->pos+1)%arp->count;
    }
    return arp->notes[arp->pos];
}

/* Pattern */
void ag_chip_pattern_init(AgChipPattern *pat) {
    memset(pat,0,sizeof(*pat));
    for (int i=0;i<AG_CHIP_PATTERN_LEN;i++) {
        pat->sq1_midi[i]=-1;
        pat->sq2_midi[i]=-1;
        pat->tri_midi[i]=-1;
        pat->sq1_duty[i]=2;
        pat->sq2_duty[i]=1;
    }
}
void ag_chip_pattern_set(AgChipPattern *pat, int step, int sq1, int sq2, int tri, int noise) {
    if (step<0||step>=AG_CHIP_PATTERN_LEN) return;
    pat->sq1_midi[step]=sq1;
    pat->sq2_midi[step]=sq2;
    pat->tri_midi[step]=tri;
    pat->noise_on[step]=noise;
}
void ag_chip_seq_init(AgChipSequencer *seq, double sr, double bpm) {
    memset(seq,0,sizeof(*seq));
    seq->sr = sr>0?sr:AG_SR_DEFAULT;
    seq->bpm = bpm>0?bpm:120.0;
    seq->step_dur = 60.0 / seq->bpm / 4.0;
    ag_chip_init(&seq->chip, sr);
    ag_chip_pattern_init(&seq->pattern);
}
void ag_chip_seq_set_pattern(AgChipSequencer *seq, const AgChipPattern *pat) {
    seq->pattern = *pat;
}
float ag_chip_seq_next(AgChipSequencer *seq) {
    seq->playhead += 1.0/seq->sr;
    if (seq->playhead >= seq->step_dur) {
        seq->playhead = 0.0;
        int step = seq->step;
        int m1 = seq->pattern.sq1_midi[step];
        int m2 = seq->pattern.sq2_midi[step];
        int m3 = seq->pattern.tri_midi[step];
        int nn = seq->pattern.noise_on[step];
        if (m1>=0) ag_chip_square_note_on(&seq->chip.sq1, (float)ag_midi_to_freq(m1), 0.6f, seq->pattern.sq1_duty[step]);
        else if (m1==-2) ag_chip_square_note_off(&seq->chip.sq1);
        if (m2>=0) ag_chip_square_note_on(&seq->chip.sq2, (float)ag_midi_to_freq(m2), 0.5f, seq->pattern.sq2_duty[step]);
        else if (m2==-2) ag_chip_square_note_off(&seq->chip.sq2);
        if (m3>=0) ag_chip_tri_note_on(&seq->chip.tri, (float)ag_midi_to_freq(m3), 0.6f);
        else if (m3==-2) ag_chip_tri_note_off(&seq->chip.tri);
        if (nn) ag_chip_noise_note_on(&seq->chip.noise, 4000.0f, 0.4f, 0);
        seq->step = (seq->step+1)%AG_CHIP_PATTERN_LEN;
    }
    return ag_chip_next(&seq->chip);
}

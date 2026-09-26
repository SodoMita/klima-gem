#include "ag_sequencer.h"
#include <string.h>
#include <math.h>

void ag_seq_init(AgSequencer *seq, double sr, float bpm, int steps_per_bar) {
    memset(seq,0,sizeof(*seq));
    seq->sr = sr>0?sr:AG_SR_DEFAULT;
    seq->bpm = bpm>0?bpm:120.0f;
    seq->steps = steps_per_bar>0?steps_per_bar:16;
    seq->step_dur = 60.0 / seq->bpm / (seq->steps/4.0);
    seq->track_count = 1;
    seq->playing = 1;
    ag_rng_seed(&seq->rng, 0x5E0);
    for (int t=0;t<AG_SEQ_MAX_TRACKS;t++) {
        seq->tracks[t].length = seq->steps;
        for (int s=0;s<AG_SEQ_MAX_STEPS;s++) {
            seq->tracks[t].steps[s].midi = -1;
            seq->tracks[t].steps[s].vel = 0.8f;
            seq->tracks[t].steps[s].gate = 0.8f;
            seq->tracks[t].steps[s].prob = 1.0f;
        }
    }
}
void ag_seq_set_bpm(AgSequencer *seq, float bpm) {
    seq->bpm = bpm>0?bpm:120.0f;
    seq->step_dur = 60.0 / seq->bpm / (seq->steps/4.0);
}
void ag_seq_set_swing(AgSequencer *seq, float swing) { seq->swing = ag_clamp_f(swing,0,0.6f); }
void ag_seq_clear_track(AgSequencer *seq, int track) {
    if (track<0||track>=AG_SEQ_MAX_TRACKS) return;
    for (int s=0;s<AG_SEQ_MAX_STEPS;s++) seq->tracks[track].steps[s].midi=-1;
}
void ag_seq_set_step(AgSequencer *seq, int track, int step_idx, int midi, float vel, float gate) {
    if (track<0||track>=AG_SEQ_MAX_TRACKS) return;
    if (step_idx<0||step_idx>=AG_SEQ_MAX_STEPS) return;
    seq->tracks[track].steps[step_idx].midi=midi;
    seq->tracks[track].steps[step_idx].vel=ag_clamp_f(vel,0,1);
    seq->tracks[track].steps[step_idx].gate=ag_clamp_f(gate,0,1);
}
void ag_seq_set_scale(AgSequencer *seq, int track, const AgScale *scale, int root_midi) {
    if (track<0||track>=AG_SEQ_MAX_TRACKS) return;
    seq->tracks[track].scale = *scale;
    seq->tracks[track].root_midi = root_midi;
    seq->tracks[track].use_scale = 1;
}
int ag_seq_tick(AgSequencer *seq) {
    if (!seq->playing) return 0;
    seq->playhead += 1.0/seq->sr;
    double dur = seq->step_dur;
    if (seq->swing>0 && (seq->current_step%2)==1) dur += seq->step_dur * seq->swing;
    if (seq->playhead >= dur) {
        seq->playhead=0.0;
        seq->current_step = (seq->current_step+1)%seq->steps;
        return 1;
    }
    return 0;
}
int ag_seq_current_step(const AgSequencer *seq) { return seq->current_step; }
void ag_seq_get_active_notes(const AgSequencer *seq, int *out_midi, float *out_vel, int *out_count, int max_notes) {
    int count=0;
    int step = seq->current_step;
    for (int t=0;t<seq->track_count && count<max_notes;t++) {
        AgStep st = seq->tracks[t].steps[step % seq->tracks[t].length];
        if (st.midi<0) continue;
        if (st.prob < 1.0f) {
            float r = ag_rng_next_f32((AgRng*)&seq->rng);
            if (r > st.prob) continue;
        }
        int midi = st.midi;
        if (seq->tracks[t].use_scale) {
            midi = ag_scale_degree_to_midi(st.midi, seq->tracks[t].root_midi, &seq->tracks[t].scale);
        }
        out_midi[count]=midi;
        out_vel[count]=st.vel;
        count++;
    }
    *out_count=count;
}

void ag_euclidean(int *out_steps, int len, int pulses, int rotation) {
    if (len<=0) return;
    if (pulses<0) pulses=0;
    if (pulses>len) pulses=len;
    for (int i=0;i<len;i++) out_steps[i]=0;
    if (pulses==0) return;
    /* Bjorklund */
    int bucket=0;
    for (int i=0;i<len;i++) {
        bucket += pulses;
        if (bucket >= len) {
            bucket -= len;
            out_steps[i]=1;
        }
    }
    if (rotation!=0) {
        int tmp[AG_SEQ_MAX_STEPS];
        for (int i=0;i<len;i++) tmp[i]=out_steps[(i+rotation)%len];
        for (int i=0;i<len;i++) out_steps[i]=tmp[i];
    }
}
void ag_seq_fill_euclidean(AgSequencer *seq, int track, int len, int pulses, int rotation, int midi, float vel) {
    if (track<0||track>=AG_SEQ_MAX_TRACKS) return;
    int steps[AG_SEQ_MAX_STEPS];
    ag_euclidean(steps, len, pulses, rotation);
    seq->tracks[track].length=len;
    for (int i=0;i<len;i++) {
        if (steps[i]) seq->tracks[track].steps[i].midi=midi;
        else seq->tracks[track].steps[i].midi=-1;
        seq->tracks[track].steps[i].vel=vel;
    }
}

/* Arp */
void ag_arpeggiator_init(AgArpeggiator *arp, double sr, float rate_hz) {
    memset(arp,0,sizeof(*arp));
    arp->sr = sr>0?sr:AG_SR_DEFAULT;
    arp->step_dur = rate_hz>0?1.0/rate_hz:0.2;
    arp->mode = AG_ARP_UP;
    arp->octave_range=1;
    ag_rng_seed(&arp->rng, 0xA19);
    arp->current_midi=-1;
}
void ag_arpeggiator_set_mode(AgArpeggiator *arp, AgArpMode mode) { arp->mode=mode; }
void ag_arpeggiator_note_on(AgArpeggiator *arp, int midi) {
    if (arp->held_count>=16) return;
    for (int i=0;i<arp->held_count;i++) if (arp->held_notes[i]==midi) return;
    arp->held_notes[arp->held_count++]=midi;
    /* sort */
    for (int i=0;i<arp->held_count-1;i++) for (int j=i+1;j<arp->held_count;j++) if (arp->held_notes[i]>arp->held_notes[j]) {
        int tmp=arp->held_notes[i]; arp->held_notes[i]=arp->held_notes[j]; arp->held_notes[j]=tmp;
    }
    arp->active=1;
}
void ag_arpeggiator_note_off(AgArpeggiator *arp, int midi) {
    int idx=-1;
    for (int i=0;i<arp->held_count;i++) if (arp->held_notes[i]==midi) { idx=i; break; }
    if (idx>=0) {
        for (int i=idx;i<arp->held_count-1;i++) arp->held_notes[i]=arp->held_notes[i+1];
        arp->held_count--;
    }
    if (arp->held_count==0) arp->active=0;
}
int ag_arpeggiator_next(AgArpeggiator *arp) {
    if (!arp->active || arp->held_count==0) return -1;
    arp->timer += 1.0/arp->sr;
    if (arp->timer < arp->step_dur) return -1;
    arp->timer=0.0;
    int count = arp->held_count * arp->octave_range;
    if (count==0) return -1;
    switch (arp->mode) {
        case AG_ARP_UP:
            arp->pos = (arp->pos+1)%count;
            break;
        case AG_ARP_DOWN:
            arp->pos = (arp->pos-1+count)%count;
            break;
        case AG_ARP_UP_DOWN:
            arp->pos += arp->dir>=0?1:-1;
            if (arp->pos>=count) { arp->pos=count-2; arp->dir=-1; if (arp->pos<0) arp->pos=0; }
            if (arp->pos<0) { arp->pos=1; arp->dir=1; if (arp->pos>=count) arp->pos=0; }
            break;
        case AG_ARP_RANDOM:
            arp->pos = (int)(ag_rng_next_f32(&arp->rng)*count) % count;
            break;
        case AG_ARP_CONVERGE: {
            /* outside in */
            int mid = count/2;
            if (arp->pos < mid) arp->pos = count-1 - arp->pos;
            else arp->pos = count-1 - arp->pos;
            arp->pos = (arp->pos+1)%count;
        } break;
        default: arp->pos=(arp->pos+1)%count; break;
    }
    int oct = arp->pos / arp->held_count;
    int idx = arp->pos % arp->held_count;
    int midi = arp->held_notes[idx] + oct*12;
    arp->current_midi=midi;
    return midi;
}
int ag_arpeggiator_current(const AgArpeggiator *arp) { return arp->current_midi; }

/* Chord */
void ag_chord_make(AgChord *out, AgChordType type, int inversion) {
    memset(out,0,sizeof(*out));
    switch (type) {
        case AG_CHORD_MAJOR: out->count=3; out->tones[0]=0; out->tones[1]=4; out->tones[2]=7; break;
        case AG_CHORD_MINOR: out->count=3; out->tones[0]=0; out->tones[1]=3; out->tones[2]=7; break;
        case AG_CHORD_DIM: out->count=3; out->tones[0]=0; out->tones[1]=3; out->tones[2]=6; break;
        case AG_CHORD_AUG: out->count=3; out->tones[0]=0; out->tones[1]=4; out->tones[2]=8; break;
        case AG_CHORD_SUS2: out->count=3; out->tones[0]=0; out->tones[1]=2; out->tones[2]=7; break;
        case AG_CHORD_SUS4: out->count=3; out->tones[0]=0; out->tones[1]=5; out->tones[2]=7; break;
        case AG_CHORD_MAJ7: out->count=4; out->tones[0]=0; out->tones[1]=4; out->tones[2]=7; out->tones[3]=11; break;
        case AG_CHORD_MIN7: out->count=4; out->tones[0]=0; out->tones[1]=3; out->tones[2]=7; out->tones[3]=10; break;
        case AG_CHORD_DOM7: out->count=4; out->tones[0]=0; out->tones[1]=4; out->tones[2]=7; out->tones[3]=10; break;
        default: out->count=3; out->tones[0]=0; out->tones[1]=4; out->tones[2]=7; break;
    }
    inversion = inversion % out->count;
    if (inversion<0) inversion+=out->count;
    for (int i=0;i<inversion;i++) {
        int first = out->tones[0];
        for (int j=0;j<out->count-1;j++) out->tones[j]=out->tones[j+1];
        out->tones[out->count-1]=first+12;
    }
}
int ag_chord_to_midi(const AgChord *chord, int root_midi, int *out_midi, int max_notes) {
    int n = chord->count < max_notes ? chord->count : max_notes;
    for (int i=0;i<n;i++) out_midi[i]=root_midi+chord->tones[i];
    return n;
}

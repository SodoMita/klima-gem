#include "ag_presets.h"
#include <string.h>

/* UI */
void ag_preset_ui_click(AgSfxParams *out) { ag_sfx_preset_click(out); out->base_freq=1200; out->gain=0.4f; }
void ag_preset_ui_hover(AgSfxParams *out) { ag_sfx_preset_blip(out); out->base_freq=800; out->gain=0.25f; out->attack=0.002f; out->sustain=0.03f; out->decay=0.03f; }
void ag_preset_ui_confirm(AgSfxParams *out) { ag_sfx_preset_chime(out, 2, 659.25f); out->gain=0.5f; }
void ag_preset_ui_back(AgSfxParams *out) { ag_sfx_preset_sweep(out, 600, 350, 0.12f); out->gain=0.45f; }
void ag_preset_ui_error(AgSfxParams *out) { ag_sfx_preset_buzz(out); out->base_freq=150; out->gain=0.5f; out->attack=0.01f; out->sustain=0.15f; out->decay=0.1f; }
void ag_preset_ui_save(AgSfxParams *out) { ag_sfx_preset_chime(out, 3, 523.25f); out->arp_speed=0.06f; out->arp_mod=4.0f; out->gain=0.5f; }
void ag_preset_ui_open(AgSfxParams *out) { ag_sfx_preset_open(out); }
void ag_preset_ui_close(AgSfxParams *out) { ag_sfx_preset_close(out); }

/* Gameplay */
void ag_preset_footstep(AgSfxParams *out, int surface) {
    ag_sfx_params_init(out, 0xF07);
    out->wave=AG_SFX_NOISE;
    out->base_freq= surface==0? 120 : surface==1? 300 : surface==2? 200 : 400;
    out->attack=0.001f; out->sustain=0.02f; out->decay=0.05f;
    out->filter_on=1; out->filter_type=AG_FILTER_BP;
    out->lpf_freq= out->base_freq*3;
    out->gain=0.5f;
}
void ag_preset_jump(AgSfxParams *out) { ag_sfx_preset_jump(out); }
void ag_preset_land(AgSfxParams *out) {
    ag_sfx_params_init(out, 0x1A2);
    out->wave=AG_SFX_NOISE;
    out->base_freq=80; out->attack=0.001f; out->sustain=0.04f; out->decay=0.12f;
    out->filter_on=1; out->lpf_freq=400; out->gain=0.6f;
}
void ag_preset_pickup(AgSfxParams *out, int type) {
    if(type==0) ag_sfx_preset_coin(out);
    else if(type==1) ag_sfx_preset_powerup(out);
    else { ag_sfx_preset_chime(out,2,880); out->base_freq=880; }
}
void ag_preset_hit(AgSfxParams *out, int hard) {
    ag_sfx_preset_hit(out);
    if(hard) { out->base_freq=300; out->gain=0.9f; out->sustain=0.08f; }
}
void ag_preset_explosion(AgSfxParams *out, int size) {
    ag_sfx_preset_explosion(out);
    if(size==0){ out->sustain=0.12f; out->decay=0.25f; out->gain=0.6f; }
    else if(size==1){ out->sustain=0.22f; out->decay=0.5f; out->gain=0.8f; }
    else { out->sustain=0.35f; out->decay=0.9f; out->gain=1.0f; out->lpf_freq=800; }
}
void ag_preset_laser(AgSfxParams *out, int type) {
    ag_sfx_preset_laser(out);
    if(type==1){ out->base_freq=800; out->freq_ramp=-1200; }
    else if(type==2){ out->base_freq=2000; out->freq_ramp=1500; }
}
void ag_preset_whoosh(AgSfxParams *out) { ag_sfx_preset_whoosh(out); }
void ag_preset_teleport(AgSfxParams *out) {
    ag_sfx_params_init(out, 0x7E1);
    out->wave=AG_SFX_SINE;
    out->base_freq=200; out->freq_ramp=2000; out->attack=0.05f; out->sustain=0.25f; out->decay=0.4f;
    out->vib_strength=20; out->vib_speed=15; out->gain=0.6f;
}
void ag_preset_heal(AgSfxParams *out) {
    ag_sfx_params_init(out, 0x4EA1);
    out->wave=AG_SFX_SINE;
    out->base_freq=400; out->freq_ramp=600; out->arp_speed=0.1f; out->arp_mod=7;
    out->attack=0.05f; out->sustain=0.4f; out->decay=0.5f; out->gain=0.55f;
}
void ag_preset_levelup(AgSfxParams *out) {
    ag_sfx_preset_powerup(out);
    out->arp_speed=0.08f; out->arp_mod=12; out->sustain=0.5f; out->gain=0.6f;
}

void ag_preset_wind_gust(AgSfxParams *out) {
    ag_sfx_params_init(out, 0xA11D);
    out->wave=AG_SFX_NOISE;
    out->filter_on=1; out->filter_type=AG_FILTER_LP;
    out->lpf_freq=600; out->lpf_ramp=400;
    out->attack=0.3f; out->sustain=0.5f; out->decay=0.6f; out->gain=0.4f;
}
void ag_preset_rain_drop(AgSfxParams *out) {
    ag_sfx_params_init(out, 0xA1);
    out->wave=AG_SFX_SINE;
    out->base_freq=2500; out->freq_ramp=-1200;
    out->attack=0.001f; out->sustain=0.02f; out->decay=0.08f; out->gain=0.3f;
}
void ag_preset_thunder(AgSfxParams *out) {
    ag_sfx_params_init(out, 0x7414);
    out->wave=AG_SFX_NOISE;
    out->base_freq=40; out->filter_on=1; out->lpf_freq=200; out->lpf_ramp=-50;
    out->attack=0.01f; out->sustain=0.4f; out->decay=1.2f; out->gain=0.8f;
}

void ag_preset_music_for_scene(const char *scene_name, AgProcSpec *out, uint64_t seed) {
    AgMood mood = AG_MOOD_CALM;
    int root = 60;
    float bpm = 80;
    if(!scene_name) scene_name="classroom";
    if(strcmp(scene_name,"classroom")==0){ mood=AG_MOOD_CALM; root=60; bpm=68; }
    else if(strcmp(scene_name,"nexus")==0){ mood=AG_MOOD_TENSE; root=74; bpm=96; }
    else if(strcmp(scene_name,"rift")==0){ mood=AG_MOOD_RIFT; root=61; bpm=128; }
    else if(strcmp(scene_name,"grove")==0){ mood=AG_MOOD_DREAM; root=64; bpm=62; }
    else if(strcmp(scene_name,"shore")==0){ mood=AG_MOOD_WARM; root=67; bpm=56; }
    else if(strcmp(scene_name,"core")==0){ mood=AG_MOOD_TENSE; root=36; bpm=72; }
    else if(strcmp(scene_name,"festival")==0){ mood=AG_MOOD_FESTIVAL; root=65; bpm=114; }
    else if(strcmp(scene_name,"lab")==0){ mood=AG_MOOD_LAB; root=69; bpm=108; }
    else if(strcmp(scene_name,"sanctum")==0){ mood=AG_MOOD_AMBIENT; root=72; bpm=48; }
    else if(strcmp(scene_name,"alley")==0){ mood=AG_MOOD_NIGHT; root=46; bpm=86; }
    else if(strcmp(scene_name,"lighthouse")==0){ mood=AG_MOOD_CALM; root=53; bpm=46; }
    else if(strcmp(scene_name,"lofi")==0){ mood=AG_MOOD_LOFI; root=60; bpm=82; }
    else if(strcmp(scene_name,"chiptune")==0){ mood=AG_MOOD_CHIPTUNE; root=60; bpm=120; }
    ag_proc_spec_from_mood(out, mood, root, bpm, seed);
}

void ag_preset_music_for_mood(const char *mood_name, AgProcSpec *out, uint64_t seed) {
    AgMood mood = ag_mood_from_string(mood_name);
    ag_proc_spec_from_mood(out, mood, 60, 0, seed);
}

void ag_preset_drum_pattern_basic(AgDrumPattern *out, float bpm) {
    ag_drum_pattern_init(out, bpm);
    ag_drum_pattern_set_kit(out,0,AG_DRUM_KICK);
    ag_drum_pattern_set_kit(out,1,AG_DRUM_SNARE);
    ag_drum_pattern_set_kit(out,2,AG_DRUM_HIHAT_CLOSED);
    ag_drum_pattern_set_step(out,0,0,100); ag_drum_pattern_set_step(out,0,4,100); ag_drum_pattern_set_step(out,0,8,100); ag_drum_pattern_set_step(out,0,12,100);
    ag_drum_pattern_set_step(out,1,4,90); ag_drum_pattern_set_step(out,1,12,90);
    for(int i=0;i<16;i+=2) ag_drum_pattern_set_step(out,2,i,60);
}
void ag_preset_drum_pattern_lofi(AgDrumPattern *out, float bpm) {
    ag_drum_pattern_init(out, bpm);
    out->swing=0.12f;
    ag_drum_pattern_set_kit(out,0,AG_DRUM_KICK);
    ag_drum_pattern_set_kit(out,1,AG_DRUM_SNARE);
    ag_drum_pattern_set_kit(out,2,AG_DRUM_HIHAT_CLOSED);
    ag_drum_pattern_set_kit(out,3,AG_DRUM_RIM);
    ag_drum_pattern_set_step(out,0,0,100); ag_drum_pattern_set_step(out,0,7,70); ag_drum_pattern_set_step(out,0,10,80);
    ag_drum_pattern_set_step(out,1,4,85); ag_drum_pattern_set_step(out,1,11,75); ag_drum_pattern_set_step(out,1,15,60);
    ag_drum_pattern_set_step(out,2,2,50); ag_drum_pattern_set_step(out,2,6,50); ag_drum_pattern_set_step(out,2,10,50); ag_drum_pattern_set_step(out,2,14,50);
    ag_drum_pattern_set_step(out,3,0,40); ag_drum_pattern_set_step(out,3,8,40);
}
void ag_preset_drum_pattern_techno(AgDrumPattern *out, float bpm) {
    ag_drum_pattern_init(out, bpm);
    ag_drum_pattern_set_kit(out,0,AG_DRUM_KICK);
    ag_drum_pattern_set_kit(out,1,AG_DRUM_HIHAT_CLOSED);
    ag_drum_pattern_set_kit(out,2,AG_DRUM_HIHAT_OPEN);
    ag_drum_pattern_set_kit(out,3,AG_DRUM_CLAP);
    for(int i=0;i<16;i+=4) ag_drum_pattern_set_step(out,0,i,100);
    for(int i=0;i<16;i+=2) ag_drum_pattern_set_step(out,1,i,70);
    ag_drum_pattern_set_step(out,2,14,80);
    ag_drum_pattern_set_step(out,3,4,90); ag_drum_pattern_set_step(out,3,12,90);
}
void ag_preset_drum_pattern_ambient(AgDrumPattern *out, float bpm) {
    ag_drum_pattern_init(out, bpm);
    ag_drum_pattern_set_kit(out,0,AG_DRUM_KICK);
    ag_drum_pattern_set_kit(out,1,AG_DRUM_CYMBAL);
    ag_drum_pattern_set_step(out,0,0,80);
    ag_drum_pattern_set_step(out,1,8,60);
}

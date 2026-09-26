#ifndef AUDIO_GEN_H
#define AUDIO_GEN_H

/* Umbrella header for the Audio Generators library
 * Include this one file to get all generators.
 *
 * This library is a collection of procedural music and sound
 * generators in pure C, designed for games (Godot) and offline
 * WAV rendering. No malloc in audio thread (except reverb/delay
 * init), deterministic RNG, portable.
 *
 * Modules:
 *  - ag_common: rng, scales, buffer helpers
 *  - ag_osc: bandlimited oscillators, wavetable, LFO
 *  - ag_envelope: ADSR, AR, multi-segment
 *  - ag_filter: biquad, one-pole, SVF, ladder, dc blocker
 *  - ag_noise: white, pink, brown, velvet, crackle
 *  - ag_sfx: sfxr-like retro SFX synth + presets (coin, laser, explosion, etc)
 *  - ag_drums: kick, snare, hihat, clap, tom, cowbell, cymbal + drum machine
 *  - ag_fm: 2-op and 4-op FM synth with presets (bass, lead, pad, bell, epiano, brass)
 *  - ag_chiptune: NES-style square/tri/noise chip + sequencer + arp
 *  - ag_ambient: drone, wind, rain, granular pad, shimmer, underwater
 *  - ag_music_box: Karplus-Strong, tine, bell, kalimba, music box sequencer
 *  - ag_sequencer: step sequencer, euclidean, arpeggiator, chord generator
 *  - ag_reverb: freeverb + schroeder
 *  - ag_delay: delay, ping-pong, tape delay with wow/flutter
 *  - ag_wav: WAV writer/reader (float32, int16)
 *  - ag_proc_music: high-level procedural music (mood-based live scores, mixer with crossfade)
 */

#include "ag_common.h"
#include "ag_osc.h"
#include "ag_envelope.h"
#include "ag_filter.h"
#include "ag_noise.h"
#include "ag_sfx.h"
#include "ag_drums.h"
#include "ag_fm.h"
#include "ag_chiptune.h"
#include "ag_ambient.h"
#include "ag_music_box.h"
#include "ag_sequencer.h"
#include "ag_reverb.h"
#include "ag_delay.h"
#include "ag_wav.h"
#include "ag_proc_music.h"
#include "ag_distortion.h"
#include "ag_sampler.h"
#include "ag_formant.h"
#include "ag_presets.h"
#include "ag_3d.h"
#include "ag_water.h"
#include "ag_fire.h"
#include "ag_nature.h"
#include "ag_weather.h"
#include "ag_biome.h"
#include "ag_ambience_3d.h"
#include "ag_soundscape.h"
#include "ag_material.h"
#include "ag_terrain.h"
#include "ag_scifi.h"
#include "ag_magic.h"

#ifdef __cplusplus
extern "C" {
#endif

#define AUDIO_GEN_VERSION_MAJOR 1
#define AUDIO_GEN_VERSION_MINOR 0
#define AUDIO_GEN_VERSION_PATCH 0
#define AUDIO_GEN_VERSION "1.0.0"

const char* audio_gen_version(void);

#ifdef __cplusplus
}
#endif

#endif

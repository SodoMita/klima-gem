# Audio Generators Library (C)

A collection of procedural music and sound generators in pure C, designed for games (Godot 4.7) and offline WAV rendering. Deterministic RNG, no malloc in audio thread (except reverb/delay init), portable (works on Android with `portable.c` fallback).

This extends the existing `SceneScore` live score mixer with many more generators for future use — now including **environment, ambient, and 3D spatialized soundscapes**.

## Modules

### Core Synthesis
- **ag_common**: RNG (xorshift64), scale helpers (major/minor/dorian/phrygian/lydian/mixolydian/pentatonic/blues/chromatic/octatonic/whole-tone), buffer utils, MIDI<->freq.
- **ag_osc**: Bandlimited oscillators (sine, saw, square, tri, noise, pulse) with polyBLEP, wavetable osc, LFO.
- **ag_envelope**: ADSR (with curve), AR, multi-segment envelope.
- **ag_filter**: Biquad (LP/HP/BP/notch/peak/shelf), one-pole LP/HP, SVF (simultaneous LP/HP/BP/notch), DC blocker, Moog ladder approx.
- **ag_noise**: White, pink (Kellet), brown, velvet (sparse impulses), crackle.
- **ag_distortion**: Distortion/tanh, bitcrusher, wavefolder, compressor.
- **ag_sampler**: Sample, voice with linear interp & pitch shift, instrument zones, poly 16.
- **ag_formant**: Formant filter, vowels A/E/I/O/U, morphing.

### Retro / Game SFX
- **ag_sfx**: sfxr-like retro SFX synth. Params: wave, base_freq, ramp, vibrato, duty, ADSR+punch, filter, phaser, repeat, arp. Presets: coin, laser, explosion, powerup, hit, jump, blip, click, sweep, chime, buzz, whoosh, open, close.
- **ag_drums**: Kick (sine sweep + click), snare (tone+noise BP), hihat (noise+metallic squares), clap (multi-burst), toms, rim, cowbell, cymbal. Drum machine pattern (16 steps, 8 tracks, swing) + euclidean.
- **ag_fm**: 2-op FM (mod+car) and 4-op FM with algorithms (stack, 3+1, 2x2). Presets: bass, lead, pad, bell, epiano, brass.
- **ag_chiptune**: NES 2A03-ish: 2 squares (4 duties), triangle, noise (LFSR long/short). Chip mixer + arpeggiator + 16-step pattern sequencer.
- **ag_music_box**: Karplus-Strong plucked string, tine (sine+overtone), bell (8 inharmonic partials), kalimba (tine+wood), music box sequencer (16 voices, 128 notes).
- **ag_sequencer**: Step sequencer (64 steps, 8 tracks, scale degree mapping), euclidean rhythm, arpeggiator (up/down/up-down/random/converge), chord generator (major/minor/dim/aug/sus2/sus4/maj7/min7/dom7 + inversion).
- **ag_presets**: High-level game presets: UI, gameplay (footstep surface, jump/land/pickup/hit/explosion/laser/whoosh/teleport/heal/levelup), ambient, music_for_scene, drum patterns.

### Music & Effects
- **ag_reverb**: Freeverb (8 combs + 4 allpass) with room_size/damping/wet/dry/width, plus cheaper Schroeder (4 combs+2 allpass).
- **ag_delay**: Delay line (feedback+LP filter), ping-pong stereo, tape delay (wow/flutter via LFO).
- **ag_proc_music**: High-level procedural music. Mood-based spec (calm/warm/tense/night/dream/lofi/chiptune/ambient/rift/festival/lab), each with scale, chord progression, gains, plucks/bass per bar, shape, drums. Live scheduler like SceneScore: queue bars ahead, spawn voices, crossfade mixer of 2 layers, optional reverb/delay and drum machine.
- **ag_wav**: WAV writer (float32, int16) and reader, plus mem writer.

### Environment & Ambient (NEW)
- **ag_3d**: 3D audio math + spatialization. Vec3 ops, Listener (pos/vel/forward/up/right), Source (pos/vel/gain/min/max/rolloff/dist model/cone), distance models (linear/inverse/exp), cone gain, Doppler pitch, stereo & binaural panning (equal-power + ITD 0.6ms + ILD), air absorption (LP fc = base*exp(-dist*0.008)), occlusion (gain + LP), Spatializer (air LP + occ LP + ITD delay buffer 1024), ReverbZone, 3D Mixer (32 sources, master gain).
- **ag_water**: Ocean (white+pink LP800 + swell LFO 0.07Hz + crash BP300 + random crash), River (pink+white LP1200 HP40 + flow LFO 0.3Hz + turbulence bursts), Stream (river + sparkle BP3500 random), Waterfall (white+pink LP2000+LP600 HP80 + roar LFO 0.12Hz), Drip (sine BP1200 ADSR 0.001/0.15 + auto random timing), Bubbles (sine rising pitch ADSR + random rate), Underwater (river LP600 + pressure LFO 0.08Hz).
- **ag_fire**: Fire (pink+white LP2500 BP800 HP40 + flicker LFO 8Hz + velvet crackle BP), Fireplace (fire + room LP1200 + LFO 0.2Hz), Torch (fire + wind LFO 1.2Hz), Bonfire (fire + brown noise LP120).
- **ag_nature**: Bird (FM chirp: sine + mod 40-120Hz + BP 2.5Q + ADSR, species sparrow/robin/crow/owl/seagull, auto density), Cricket (2 sines 4500/4600 + AM LFO 30Hz + ADSR), Cicada (white BP4000 Q3 + AM 120Hz + random fc 3500-5000), Frog (sine 150-350 + BP formant 2.5x + ADSR), InsectSwarm (16 grains sine 3000-8000 random pan), Owl (sine 400 LP800 ADSR 0.05/0.4).
- **ag_weather**: RainSystem (white LP4000 + BP2500 random drops density*0.15, types light/med/heavy/hail/snow), Thunder (brown+white LP200 BP80 + rumble LFO 0.08Hz + ADSR 0.05/1.5, auto storm intensity), WindSystem (white+pink LP800+LP400 + gust LFOs 0.11/0.23Hz + turbulence LFO 1.5Hz), WeatherMixer (rain+thunder+wind stereo).
- **ag_biome**: BiomeParams (type/wind/water/birds/insects/fire/weather/time_of_day/humidity/seed), Biome (wind, ocean, river, stream, waterfall, drip, fire, 4 birds, 2 crickets, 2 cicadas, 2 frogs, 1 owl, swarm, weather, drone 55Hz, granular 110Hz). Types: forest, cave, desert, ocean, city, mountain, jungle, swamp, tundra, grassland, river, beach, nexus, rift, lab. Params per biome: e.g., forest wind0.3 water0.2 birds0.7 insects0.5, cave wind0.1 water0.6, etc. Time-of-day: day_factor = sin(tod*PI) affects birds vs crickets, night owls. Render stereo.
- **ag_ambience_3d**: 3D Ambience System. Listener, layers (8: bed/point/zone/reverb), point sources (16), reverb zones (4), WeatherMixer, BiomeParams, time, time_of_day, weather_intensity, RNG. Layers have gain ramping, biome, zone pos/radius, gen_type. Init, set_listener (pos/forward/up/vel), set_biome, set_weather, add_point_source (pos/min/max/gain), set_point_pos/gain, remove, add_reverb_zone, set_master_gain. Render: layers (biome beds) + point sources (procedural sine+noise placeholder, spatialized via Spatializer) + weather + reverb zones (reverb_gain = (1-d/radius)*gain). Presets: forest, cave (reverb zone 20m 0.8), ocean, city, nexus (reverb 30m), for_scene (maps scene names to biome + reverb).
- **ag_soundscape**: High-level evolving soundscape combining biome + weather + music + 3D. Params: biome, mood, weather, weather_intensity, time_of_day, music_gain, ambience_gain, master_gain, seed, use_3d, use_music. Init creates Ambience3D (preset for scene), Biome, ProcMixer (mood), WeatherMixer. Set_params with fade, set_time_of_day, set_weather, set_mood (transitions proc mixer). Render: temp buffers for amb (3D or biome), music (proc mixer), weather, mix = amb*amb_gain + music*music_gain + weather*weather_intensity*0.5, soft clip, master_gain. Presets for Chrono Nexus scenes: classroom (city calm), grove (forest dream), shore (beach warm), nexus (nexus tense), rift (rift rift), core (cave tense), lab (lab lab), festival (city festival), sanctum (cave ambient), alley (city night rain light), lighthouse (ocean calm).

## Build

```sh
cd native/audio_gen
./build.sh        # host tests + gen_samples + gen_env (if zig, also GDExt)
make test         # run test_all
make samples      # gen_samples -> /tmp/ag_*.wav (basic)
./bin/gen_env     # environment/3D -> /tmp/ag_env_*.wav, ag_biome_*.wav, ag_amb3d_*.wav, ag_soundscape_*.wav, ag_3d_*.wav, ag_weather_*.wav
```

- Host tests: `bin/test_all` (all modules)
- Sample generators: `bin/gen_samples` (SFX/drums/FM/ambient/musicbox/proc/chiptune) + `bin/gen_env` (3D/water/fire/nature/weather/biomes/3D ambience/soundscapes)
- GDExtension: if `zig` is available, builds `addons/audio_gen/bin/libaudio_gen.*`

## Usage in C

```c
#include "audio_gen.h"

// SFX
AgSfxParams sp; ag_sfx_preset_coin(&sp);
float buf[44100]; ag_sfx_render(&sp, buf, 44100, 44100);
ag_wav_write_f32("coin.wav", buf, 44100, 1, 44100);

// 3D spatialized fire
AgListener lis; ag_listener_init(&lis, ag_vec3(0,0,0));
AgSource src; ag_source_init(&src, ag_vec3(5,0,-3));
AgSpatializer spat; ag_spatializer_init(&spat, 44100);
float l,r; ag_spatializer_process(&spat, &src, &lis, 0.5f, &l, &r);

// Biome
AgBiomeParams bp; ag_biome_params_default(&bp, AG_BIOME_FOREST);
bp.seed=123; bp.time_of_day=0.5f;
AgBiome biome; ag_biome_init(&biome, &bp, 44100);
float stereo[44100*2]; ag_biome_render(&biome, stereo, 44100);

// 3D Ambience for scene
AgAmbience3D amb; ag_ambience_3d_init(&amb, 44100, ag_vec3(0,0,0));
ag_ambience_3d_preset_for_scene(&amb, "grove");
ag_ambience_3d_render(&amb, stereo, 44100);

// Full soundscape (biome+music+weather+3D)
AgSoundscapeParams ssp; ag_soundscape_params_for_scene("shore",&ssp,42);
AgSoundscape ss; ag_soundscape_init(&ss, &ssp, 44100);
ag_soundscape_render(&ss, stereo, 44100);
```

## Godot Integration

GDExtension `AudioGen` (RefCounted):

- `render_sfx(type:int, frames:PackedVector2Array)` - 0=coin,1=laser,2=explosion,3=powerup,4=hit,5=jump,6=blip
- `render_drum(type:int, frames:PackedVector2Array)` - 0=kick,1=snare,2=hihat closed, etc.
- `render_fm(preset:int, frames:PackedVector2Array, freq:float)`
- `render_proc(frames:PackedVector2Array)` - proc mixer
- `transition(mood:int, root:float, bpm:float, fade:float)` - mood 0=calm,1=warm,2=tense,3=night,4=dream,5=lofi,6=chiptune,7=ambient,8=rift,9=festival,10=lab

GDScript wrapper `addons/audio_gen/audio_gen.gd` provides same API with fallback synthesis, plus `save_wav()`.

For 3D ambient, use `audio_gen_3d.gd` (new) which wraps AgAmbience3D concepts in GDScript: listener, point sources, biomes, weather.

Example:

```gdscript
var gen = AudioGen.new()
gen.transition(5, 60, 82, 0.8) # lofi
var buf = PackedVector2Array()
buf.resize(1024)
gen.render_proc(buf)
playback.push_buffer(buf)

var amb = preload("res://addons/audio_gen/audio_gen_3d.gd").new()
amb.set_biome("forest", 0.5) # noon
amb.set_weather("rain_light", 0.6)
# in _process, get stereo buffer
var env_buf = amb.render(1024)
```

## Future Ideas

- HRTF from MIT KEMAR dataset
- Occlusion raycasting integration
- Wavetable morphing synth
- Physical modeling (bowed string, reed)
- Granular cloud with sample import
- Spectral freeze / FFT
- Multi-band compressor for mastering
- MIDI file import -> procedural variation
- Live coding REPL

## License

Same as project (see LICENSE.txt). Pure C, no external deps except libm.

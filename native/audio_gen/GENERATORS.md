# Audio Generators Catalog

This document catalogs all C generators in `native/audio_gen/` for future use in Chrono Nexus and other projects.

## 1. Oscillators (`ag_osc`)

Bandlimited oscillators using polyBLEP for anti-aliased saw/square.

- Types: SINE, SAW, SQUARE, TRI, NOISE, PULSE, SAW_TRI morph
- `AgOsc`: phase 0..1, freq, sr, pw, detune, RNG for noise
- `ag_osc_next()` = bandlimited, `ag_osc_next_raw()` = naive
- Wavetable: 1024 samples, morph between tables
- LFO: wrapper with depth/offset

Use for: any synth voice, modulation.

## 2. Envelopes (`ag_envelope`)

- ADSR with curve per stage (pow shaping)
- AR (attack-release) for one-shots
- Multi-segment: up to 16 points, each with time/value/curve, optional loop

Presets: pluck, pad, bass, stab, perc(decay)

## 3. Filters (`ag_filter`)

- Biquad: LP, HP, BP, Notch, Peak, LowShelf, HighShelf (RBJ cookbook)
- One-pole LP/HP (cheap)
- SVF: simultaneous LP/HP/BP/Notch, with ic1eq/ic2eq state
- DC blocker: y = x - x1 + 0.995*y1
- Ladder: 4-pole Moog approx with tanh saturation and resonance

## 4. Noise (`ag_noise`)

- White: uniform -1..1
- Pink: Paul Kellet 1-pole filter bank
- Brown: leaky integrator
- Velvet: sparse -1/0/1 impulses, density param = avg distance
- Crackle: occasional cubed white spikes

## 5. SFX Synth (`ag_sfx`)

sfxr-inspired but cleaner. One voice = osc + vibrato LFO + LP/HP + AR + punch + phaser.

Params:
- wave, base_freq, freq_ramp, freq_dramp, vib_strength/speed, duty/duty_ramp
- attack/sustain/punch/decay, filter_on/type/lpf_freq/ramp/resonance/hpf_freq/ramp
- phaser_offset/ramp, repeat_speed, arp_speed/mod, gain, seed

Presets:
- coin: square 800Hz +1200 ramp, short
- laser: saw 1200Hz -2800 ramp
- explosion: noise 200Hz + LP 1200 -2000 ramp
- powerup: sine 300 +1800 ramp + arp 12 semitones
- hit, jump, blip, click, sweep, chime, buzz, whoosh, open, close

Render: `ag_sfx_render(params, out_mono, max_frames, sr)` or stereo.

## 6. Drums (`ag_drums`)

Each drum = osc(s) + noise + envelopes + filter.

- Kick: sine 60Hz * tune, pitch env *6, click = sin(3000Hz)*exp(-800t)*snap, tanh punch
- Snare: tone 180Hz + noise BP 2000Hz, snap transient
- Hihat: white noise + 6 square oscs at 3k+ for metallic, HP 4000
- Clap: 3 bursts, BP 1200+ burst*200
- Tom: sine with pitch env
- Rim: sine 1200Hz + noise click
- Cowbell: two sines 540Hz and 810Hz
- Cymbal: HP noise

Drum machine: 8 tracks, 16 steps, velocity 0..127, swing 0..0.6, pattern kits.

Euclidean: Bjorklund algorithm for rhythm.

## 7. FM Synth (`ag_fm`)

- 2-op: mod -> car, mod_index depth, feedback on mod
- 4-op: 4 algorithms (stack, 3+1, 2x2, 1+3)
- Op: osc (sine), env, level, freq_mul, detune

Presets:
- Bass: 1x mult, index 2.5, short ADSR
- Lead: index 4.0
- Pad: mod 0.5x, index 1.5, long pad ADSR
- Bell: mod 3.5x, index 6.0, long decay
- EPIANO: index 2.0, decay 0.6/0.8
- Brass: attack 0.08, index 3.0

## 8. Chiptune (`ag_chiptune`)

NES 2A03-ish:

- Square: phase, duty 12.5/25/50/75%, volume, ADSR, sweep placeholder
- Tri: phase, linear counter placeholder
- Noise: 15-bit LFSR, long (bit1 ^ bit0) vs short (bit6 ^ bit0), freq controls shift rate
- Chip: 2 squares + tri + noise, master gain, soft clip mix
- Arp: holds up to 8 notes, modes up/down/up-down/random/converge, octave range
- Sequencer: 16-step pattern with sq1/sq2/tri midi (-1 rest, -2 note-off) + noise on + duty, bpm, step_dur

## 9. Ambient (`ag_ambient`)

- Drone: 3 sines detuned (0, +detune, -detune*0.5), LP filter, LFO 0.1Hz depth 0.3, tiny white noise
- Wind: white+pink -> LP 800 + LP 400, gust LFO 0.15Hz, one-pole smooth 2Hz for envelope
- Rain: random drops (density 0..1 controls prob 0.1* density), each drop = white noise BP 1500-6000Hz, gain 0.3-1.0, plus drizzle
- Granular pad: cloud of 32 grains, each grain = 2 cycles sine * Hanning window, random pan, grain rate 20Hz, spread detune, LP filter
- Shimmer: delay line 44100 samples (1 sec), feedback 0.6, LP 3000, osc 2x base_freq for pitch mod (simulates octave up)
- Underwater: LP 600 + LFO 200 mod, HP 20

## 10. Music Box (`ag_music_box`)

- Karplus-Strong: delay line up to 4096, initial noise, feedback 0.995, LP in loop, damping
- Tine: sine + overtone 4x, ADSR 0.001/0.8/0/0.2, LP 6* freq
- Bell: 8 partials ratios 1,2,2.4,3,4.2,5.4,6.8,8, amps decreasing, decays 1..0.2, env *= (1 - 0.001/decay)
- Kalimba: tine + wood (KS 0.5x freq, 0.3 damping) mix 0.7
- MusicBox: 16 voices, 128 notes, each note time/midi/vel, playhead, next_note index, looping, render

## 11. Sequencer (`ag_sequencer`)

- Step: midi -1 rest, vel, gate, prob
- Track: 64 steps, length, root_midi, scale, use_scale flag (midi as degree)
- Sequencer: 8 tracks, steps per bar, bpm, sr, playhead, step_dur = 60/bpm/(steps/4), swing, rng, playing flag
- Tick: advances playhead, returns 1 on new step, swing adds to odd steps
- Euclidean: bucket method
- Arpeggiator: held_notes 16, pos, dir, mode, timer, step_dur, octave_range, current_midi
- Chord: types major/minor/dim/aug/sus2/sus4/maj7/min7/dom7, inversion rotates tones +12

## 12. Reverb (`ag_reverb`)

- Freeverb: 8 combs (tunings 1116,1188,1277,1356,1422,1491,1557,1617 scaled by sr/44100), 4 allpass (556,441,341,225), feedback 0.28+0.7*room_size, damping 0.4* damping, wet/dry/width/gain
- Schroeder: 4 combs + 2 allpass, simpler

## 13. Delay (`ag_delay`)

- Delay: circular buffer size = sr*max_delay_ms/1000, delay_ms, feedback, wet/dry, optional LP filter
- PingPong: left delay + right delay 1.5x, cross_feedback
- Tape: delay + wow LFO 0.5Hz depth 0.002 + flutter LFO 6Hz depth 0.001 modulating delay time

## 14. Distortion (`ag_distortion`)

- Dist: drive 1..20 * tanh, mix, tone LP (one-pole placeholder)
- Bitcrush: bit_depth 1..16 steps = 2^bits, sample_rate_div 1..100, hold time = div/sr, quantize
- Wavefolder: threshold, gain, fold via fmod
- Compressor: threshold_db, ratio, attack_ms, release_ms, makeup_db, env follower with attack/release rates exp(-1/(ms*sr))

## 15. Sampler (`ag_sampler`)

- Sample: float* mono, frames, sr, owned flag
- Voice: sample ptr, pos double, inc = 2^(semi/12), gain, pan_l/r, active, loop start/end
- Next: linear interpolation, loop or stop
- Instrument: up to 16 zones, each sample + root/low/high midi + tune cents
- Poly: 16 voices, find zone by midi, pitch = midi - root + tune/100

## 16. Formant (`ag_formant`)

- Formant: freq, bw, gain
- Vowel: name + 3 formants (A: 800/80,1150/90,2900/120; E: 400/70,1700/80,2600/100; etc)
- Filter: 3 BP biquads, Q = freq/bw
- Voice: saw source + formant filter
- Morph: interpolate freq/bw/gain between two vowels

## 17. Presets (`ag_presets`)

High-level game audio:

- UI: click, hover, confirm, back, error, save, open, close
- Gameplay: footstep (surface 0 grass 120Hz,1 stone 300,2 wood 200,3 metal 400 BP), jump, land (noise 80Hz LP400), pickup (coin/powerup/key), hit soft/hard, explosion small/med/large, laser, whoosh, teleport (200+2000 ramp vib), heal, levelup
- Ambient: wind_gust LP600+400 ramp, rain_drop sine 2500-1200, thunder noise 40Hz LP200
- Music: for_scene (classroom/nexus/rift/grove/shore/core/festival/lab/sanctum/alley/lighthouse/lofi/chiptune) -> mood/root/bpm mapping, for_mood
- Drum patterns: basic (kick 0,4,8,12 snare 4,12 hihat even), lofi (swing 0.12, kick 0,7,10 snare 4,11,15 rim), techno (kick 4/4 hihat 2/2 open 14 clap 4,12), ambient (kick 0 cymbal 8)

## 18. Procedural Music (`ag_proc_music`)

High-level live score, similar to SceneScore but more genres.

- Spec: mood enum, bpm, root_midi, scale, progression[8] chords, prog_len, pad/pluck/bass/drums gains, plucks_per_bar, bass_hits_per_bar, pluck_shift/bass_shift, shape, seed, id
- from_mood: maps mood to scale/chords/gains/bpm (e.g., calm pentatonic major, tense minor dim, lofi dorian min7/dom7/maj7, ambient whole-tone, rift octatonic, etc)
- ProcMusic: spec, rng, playhead, next_bar, bar_len=60/bpm*4, bar_index, queue[256] sorted by time, voices[64], gain ramping, reverb/delay optional, drum machine if drums_gain>0
- schedule_bar: pads = chord tones +12, dur 1.15*bar, pan alternating; bass = root+shift at 0.5*bar intervals; plucks = chord[(i+bar)%count]+shift, octave up every 3rd if >=8 plucks, pan random
- Render: block 256, schedule ahead, spawn due, mix voices with shape (0 sine,1 asin warm,2 hard clip 0.72), saturation, gain ramp, reverb/delay, drums
- Mixer: 2 layers, primary index, master gain ramp, transition crossfades (retiring layer gain->0), adjust keeps id/seed but updates bpm and next_bar, reseed changes rng, active check

## 19. 3D Audio (`ag_3d`)

- Vec3 math: add/sub/mul/dot/cross/len/norm/dist
- Listener: pos/vel/forward/up/right, speed_of_sound 343, doppler_factor, air_absorption
- Source: pos/vel/gain/min_dist/max_dist/rolloff/dist_model/cone (dir/inner/outer/outer_gain), is_ambient
- Distance models: linear (1-roll*(d-min)/(max-min)), inverse (min/(min+roll*(d-min))), exp (pow(min/d, roll)), none
- Cone gain: angle = acos(dot(to_listener, cone_dir)), lerp outer_gain
- Doppler: pitch = (c + v_l*dot)/(c + v_s*dot), clamped 0.25..4
- Panning stereo: right_dot = dot(dir, right), forward_dot = dot(dir, forward), pan = right_dot * (0.7 if behind), equal-power cos/sin, ITD 0.3ms*pan, ILD 6dB*pan; binaural enhances ITD*1.2 ILD*1.5
- Air absorption: fc = base*exp(-dist*0.008)
- Occlusion: gain 1-ob*0.8, LP fc 4000*(1-ob*0.8)+200
- Spatializer: air LP L/R, occ LP L/R, ITD buffer 1024, occlusion, process mono->stereo with attenuation*cone*occ_gain * pan gains + air LP + occ LP + ITD delay
- ReverbZone: pos/radius/reverb_gain/damping/room_size, gain = (1-d/radius)*reverb_gain
- 3D Mixer: 32 sources, listener, spatializers, gains, active, sr, master_gain, add_source, set_pos, set_listener, render (in_mono_per_source [src*frames] -> stereo interleaved, peak return)

## 20. Water (`ag_water`)

- Ocean: white 0.2 + pink 0.8 -> LP800 + swell LFO 0.07Hz * strength + crash LFO 0.15Hz + random crash BP300 burst 0.02 chance every 2 sec
- River: pink 0.7 + white 0.3 -> LP1200 HP40 + flow LFO 0.3Hz turbulence + burst 0.001 chance
- Stream: river + sparkle BP3500 chance 0.02
- Waterfall: white 0.4 + pink 0.6 -> LP2000 + LP600 low roar + HP80 + roar LFO 0.12Hz
- Drip: sine BP 2.5Q ADSR 0.001/0.15, trigger freq/gain, auto random interval 0.2-2s / density
- Bubbles: sine rising pitch (freq+=freq*0.0005 per sample) ADSR, random interval 0.1-0.8s / (rate*0.3+0.1)
- Underwater: river + LP600 muffle + pressure LFO 0.08Hz mod fc 500±200

## 21. Fire (`ag_fire`)

- Fire: pink 0.5 + white 0.2 -> LP2500 HP40 + flicker LFO 8Hz, crackle = white^3 BP800 chance density*0.02, mix base 0.7 + crackle 0.6
- Fireplace: fire + room LP1200 + LFO 0.2Hz, mix fire 0.6 + room 0.4+lfo
- Torch: fire + wind LFO 1.2Hz *0.2
- Bonfire: fire + brown LP120 rumble 0.3

## 22. Nature (`ag_nature`)

- Bird: FM chirp sine + mod 40-120Hz 200Hz depth + BP 2.5Q + ADSR 0.01/0.12, species 0 sparrow 2000Hz,1 robin 2500,2 crow 3000,3 owl 3500,4 seagull 4000, auto timer 0.5-4s / density
- Cricket: 2 sines 4500/4600 + AM LFO 30Hz, ADSR 0.005/0.08, next_chirp 0.1-0.4s, trigger immediately
- Cicada: white BP4000 Q3 + AM 120Hz, random fc 3500-5000 every 0.5s
- Frog: sine 150-350 + BP formant 2.5x freq Q1.2 + ADSR 0.01/0.25, next_croak 0.8-3s
- InsectSwarm: 16 grains sine 3000-8000 random pan, spawn chance density*0.2 every 0.05s, decay 0.98
- Owl: sine 400 LP800 ADSR 0.05/0.4, next_hoot 2-6s

## 23. Weather (`ag_weather`)

- RainSystem: white LP4000 + BP2500 drops density*0.15 chance every 0.005s, freq 1500-6000 (hail 2000-8000, snow 800-2000), types light density0.15 gain0.25, med 0.35/0.45, heavy 0.7/0.7, thunderstorm 0.6/0.6, etc, gain *=0.5+intensity*0.5
- Thunder: brown 0.6 + white 0.2 -> LP200 BP80 + rumble LFO 0.08Hz, ADSR 0.05/1.5, active 0.8-2.5s, auto next 3-12s / intensity, trigger chance intensity*0.5
- WindSystem: white 0.25 + pink 0.75 -> LP800+LP400 + gust LFOs 0.11/0.23Hz + turbulence LFO 1.5Hz, env = base + (gust1*0.5+gust2*0.3)*gust + turb*0.2
- WeatherMixer: rain+thunder+wind stereo (wind slight stereo l+0.1 r-0.05)

## 24. Biome (`ag_biome`)

- BiomeParams: type, wind, water, birds, insects, fire, weather, weather_type, time_of_day 0..1 (0 midnight,0.5 noon), humidity, seed
- Default per type: forest wind0.3 water0.2 birds0.7 insects0.5 hum0.6, cave wind0.1 water0.6 birds0 insects0.1 hum0.9, desert wind0.6 water0 birds0.1 insects0.3 hum0.1, ocean wind0.5 water1 birds0.3 hum0.8, city wind0.2 water0.1 birds0.2, mountain wind0.7 water0.2 birds0.3, jungle wind0.2 water0.5 birds0.9 insects0.9 hum0.9, swamp wind0.15 water0.7 birds0.3 insects0.8 hum0.9, tundra wind0.8 water0.1, grassland wind0.4 water0.1 birds0.6 insects0.6, river wind0.2 water0.9 birds0.5 insects0.4, beach wind0.4 water0.8 birds0.4 insects0.2 hum0.7, nexus wind0.3 water0.3 birds0.2 insects0.2, rift wind0.5 water0.1, lab wind0.05
- Biome: params, wind, ocean, river, stream, waterfall, drip, fire, 4 birds, 2 crickets, 2 cicadas, 2 frogs, 1 owl, swarm, weather, drone 55Hz, granular 110Hz, RNG, sr, gain. Init all generators, time_of_day affects day_factor = sin(tod*PI) for birds vs crickets, night_factor =1-day. Render: wind*wind + water (ocean/river/stream/drip based on type)*water + birds (auto density * (0.5+tod*0.5)) + insects (day: cicada+swarm, night: cricket, swamp/jungle: frogs, night: owls)*insects + fire*fire + weather*weather + drone for cave/nexus/rift + granular for nexus, soft clip.

## 25. 3D Ambience (`ag_ambience_3d`)

- Layer types: BED (stereo bed), POINT (3D point), ZONE (area), REVERB
- Layer: type, active, gain ramping, source, spatializer, biome (has_biome), zone pos/radius, gen_type
- Ambience3D: listener, layers 8, point sources 16 (source/spat/gain/active), reverb + 4 reverb zones, biome_params, weather, sr, master gain ramping, time, time_of_day, weather_intensity, RNG
- Init: listener, reverb (room 0.5 damp 0.5 wet 0.25 dry 0.85), weather, biome_params forest, tod 0.5, RNG, spatializers
- Set listener, set biome (updates layers with biome), set weather, add point source (pos/min/max/gain), set pos/gain, remove, add reverb zone (pos/radius/gain/damp/room), set master gain
- Render: time+=1/sr, mix layers (biome beds) + point sources (procedural sine+noise placeholder spatialized) + weather + reverb zones (gain sum, set reverb wet = gain*0.4, process stereo), master gain, soft clip
- Presets: forest (biome forest layer 0.6), cave (forest? actually cave layer 0.5 + reverb zone 20m 0.8), ocean (ocean layer 0.7), city (city layer 0.4), nexus (nexus layer 0.6 + reverb 30m 0.6), for_scene maps scene names to biome via ag_biome_from_string + reverb for cave/nexus

## 26. Soundscape (`ag_soundscape`)

- Params: biome, mood, weather, weather_intensity, time_of_day, music_gain, ambience_gain, master_gain, seed, use_3d, use_music
- Default: forest/calm/clear/tod0.5 music0.6 amb1.0 master1.0 seed1 use_3d1 use_music1
- For scene: classroom city calm tod0.6 music0.4 amb0.3, grove forest dream tod0.5 music0.45 amb0.6, shore beach warm tod0.6 music0.4 amb0.7, nexus nexus tense tod0.5 music0.5 amb0.6, rift rift rift tod0.2 music0.6 amb0.5, core cave tense tod0, lab lab lab tod0.7 music0.5 amb0.2, festival city festival tod0.8 music0.6 amb0.5, sanctum cave ambient tod0.3 music0.5 amb0.6, alley city night tod0.1 music0.45 amb0.4 rain light 0.3, lighthouse ocean calm tod0.4 music0.4 amb0.7
- Soundscape: params, ambience_3d, biome fallback, proc mixer music, weather mixer, sr, time, gain, RNG
- Init: ambience_3d preset for scene, set biome/weather, biome, proc mixer transition mood seed, weather mixer
- Set params with fade (transitions proc mixer, sets ambience master, etc), set time_of_day, set weather, set mood
- Render: malloc temp buffers amb/music/weather (frames*2), amb = 3D or biome, music = proc mixer, weather = weather mixer next stereo, mix = amb*amb_gain + music*music_gain + weather*weather_intensity*0.5, soft clip, master_gain. Presets for scenes.

## 27. WAV (`ag_wav`)

- Write float32 (format 3) or int16 (format 1), header 44 bytes little-endian
- Mem writer: realloc buffer, same header
- Reader: info (channels/sr/frames/bits/is_float), read float32 or int16 -> float

## Usage Example

```c
AgProcSpec spec;
ag_proc_spec_from_mood(&spec, AG_MOOD_LOFI, 60, 82, 12345);
spec.id=1;
AgProcMixer mixer;
ag_proc_mixer_init(&mixer, 44100);
ag_proc_mixer_transition(&mixer, &spec, 0.8f);
float buf[1024*2];
ag_proc_mixer_render(&mixer, buf, 1024);
```

All generators are deterministic with seed, no malloc in audio thread after init, portable.

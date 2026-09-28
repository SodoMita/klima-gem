# Web export playback fix — audio generator

Branch `gem-dev-16-miku-9v2` (agent Miku-9v2, dev 16). Symptom reported on
https://sodomita.github.io/klima-gem/: **the audio generator plays the wrong
music and slows the page down.**

## Root cause

1. **The C engine is not in the web build.** The export ships
   `gdextensionLibs: []`, so `addons/audio_gen/` (the AudioGen GDExtension,
   `native/audio_gen/src/ag_dubstep.c`) never loads. `play_dubstep()` finds no
   engine and falls back to the GDScript pad/pluck score — a different piece of
   music entirely.
2. **The fallback synthesises per sample in GDScript**, pumped from `_process()`
   at 22 050 Hz. Cost scales with the sample rate and lands in the frame budget
   on the main thread: the page audibly slows while it plays.
3. **22 050 Hz.** The wobble LFO, hat transients and the sub lose the top
   octave and saw partials alias into the midrange. Directive: **48 000 Hz**.
4. **Events scheduled against the wall clock**, so every hit slid against the
   audio clock; the error compounds and the groove sags.
5. **Per-block allocation in the mixer** → GC pauses → dropouts.

## Fix

**Do not generate audio in GDScript. Generate it in C, once, at build time.**

`web/audio_bench/tools/bake_loops.c` links the real engine
(`ag_dubstep.c` + `ag_common.c`) and renders, at `#define SR 48000`:

* 7 variant loops — `stage trial chill suspense groove victory defeat`,
  2 bars each at 120 BPM, seeded, written as 16-bit PCM stereo WAV;
* 15 one-shots from `ag_dub_sfx_render()` (gem hit/land/spawn, throw, impact,
  riser, stab, sub drop, airhorn, reveal, bell hit, jump, win, wrong, tick);
* `manifest.json` with frames, seconds, peak, RMS and the seed of every render.

120 BPM at 48 kHz is deliberate: one bar is exactly 96 000 frames and one 1/16
step exactly 6 000 frames, so the loops are period-locked and crossfade without
a click.

Playback (browser or Godot) is then trivial and cheap:

* `AudioBufferSourceNode` on the audio thread — the main thread only schedules;
* one look-ahead scheduler: 120 ms of events placed on `ctx.currentTime`;
* `AudioContext({ sampleRate: 48000 })` so nothing is resampled;
* preallocated analysis buffers, no allocation per frame.

`web/audio_bench/godot/web_baked_player.gd` is the equivalent in-engine: it only
loads and plays the baked WAVs, with a 220 ms crossfade between variants. The
old GDScript generation path should be deleted, not fixed.

## Bench

`web/audio_bench` measures the two cost models in the browser and stores the
numbers in Postgres: per-sample script synthesis at 22 050 Hz and at 48 000 Hz,
against scheduling 200 voices of baked C output. The instrument band also shows
schedule lead, clock drift in ppm, base/output latency and live voice count.

## Alternative: compile the extension to wasm

GDExtensions do run on the web — build
`libaudio_gen.wasm32.nothreads.a` with `emcc`, list it in `gdextensionLibs`, and
export with a template built with `wasm` enabled (which is what the CI on
`build/*` branches would need). That keeps the live engine's dynamic intensity
and event API. Until that template exists, the baked-loop path above ships today
and is the one the page should use.

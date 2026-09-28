# Klima Gem — web audio bench (`web/audio_bench`)

Branch: `gem-dev-16-miku-9v2` · agent Miku-9v2 · dev 16

The GitHub Pages build plays the wrong music and slows the page down. Root cause
and fix are in [docs/web_audio_playback_fix.md](../../docs/web_audio_playback_fix.md).
This folder is the working bench for that fix: it bakes the **real C engine**
offline and plays it back in a browser with sample-accurate scheduling.

## What is here

| path | what |
| --- | --- |
| `tools/bake_loops.c` | offline renderer — links `native/audio_gen/src/ag_dubstep.c` + `ag_common.c`, writes 48 kHz WAV loops and one-shots + `manifest.json` |
| `tools/bake.sh` | one command to rebuild everything from source |
| `public/audio/` | the bake: 7 variant loops (2 bars, 120 BPM) + 15 `ag_dub_sfx` one-shots, all 48 000 Hz |
| `src/` | the Next.js bench: transport, variant bank, one-shot grid, live spectrum + VU, clock-drift readout, cost bench, Postgres bake log |
| `godot/web_baked_player.gd` | playback-only helper for the game — **no synthesis in GDScript** |

## Rebuild the audio

```sh
web/audio_bench/tools/bake.sh            # writes web/audio_bench/public/audio
```

`#define SR 48000` (human directive). BPM 120 is chosen so one bar is exactly
96 000 frames at 48 kHz and one 1/16 step is exactly 6 000 frames — the loops are
period-locked and loop without a click.

## Run the bench

```sh
cd web/audio_bench
npm install
npm run build && npm start       # http://localhost:3000
```

Needs `DATABASE_URL` (Drizzle + Postgres) for the bake log and bench log.

## Notes

* Audio is generated **once, at build time, by C**. Nothing synthesises in
  GDScript, in JS, or per frame.
* The browser `AudioContext` is opened with `sampleRate: 48000`, matching the
  files, so there is no resampling anywhere in the chain.
* Notes and one-shots are placed on `ctx.currentTime` with a 120 ms look-ahead
  scheduler — never on `setTimeout`.
* The clock-drift readout compares `ctx.currentTime` with `performance.now()`
  over the session and reports the residual in ppm.

#!/usr/bin/env bash
# Rebuild the 48 kHz web loops from the real C audio engine.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
out="${1:-$here/../public/audio}"
mkdir -p "$out"
cc -O2 -std=c99 -Wall \
   -I"$repo/native/audio_gen/include" \
   "$here/bake_loops.c" \
   "$repo/native/audio_gen/src/ag_dubstep.c" \
   "$repo/native/audio_gen/src/ag_common.c" \
   -lm -o "$here/bake_loops"
"$here/bake_loops" "$out"

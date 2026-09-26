#!/bin/sh
# Build Audio Generators library and tests
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/native/audio_gen"
OUT="$SRC/bin"
INCLUDE="$SRC/include"
ZIG="${ZIG:-zig}"
CC="${CC:-cc}"

mkdir -p "$OUT"

SRCS="$SRC/src/ag_common.c $SRC/src/ag_osc.c $SRC/src/ag_envelope.c $SRC/src/ag_filter.c $SRC/src/ag_noise.c $SRC/src/ag_sfx.c $SRC/src/ag_drums.c $SRC/src/ag_fm.c $SRC/src/ag_chiptune.c $SRC/src/ag_ambient.c $SRC/src/ag_music_box.c $SRC/src/ag_sequencer.c $SRC/src/ag_reverb.c $SRC/src/ag_delay.c $SRC/src/ag_wav.c $SRC/src/ag_proc_music.c $SRC/src/ag_distortion.c $SRC/src/ag_sampler.c $SRC/src/ag_formant.c $SRC/src/ag_presets.c $SRC/src/ag_3d.c $SRC/src/ag_water.c $SRC/src/ag_fire.c $SRC/src/ag_nature.c $SRC/src/ag_weather.c $SRC/src/ag_biome.c $SRC/src/ag_ambience_3d.c $SRC/src/ag_soundscape.c $SRC/src/audio_gen.c"

echo "=== Building tests with host cc ==="
$CC -std=c11 -O2 -I "$INCLUDE" -I "$SRC/../scene_score" $SRCS "$SRC/tests/test_all.c" -o "$OUT/test_all" -lm
echo "Running test_all..."
"$OUT/test_all"

$CC -std=c11 -O2 -I "$INCLUDE" $SRCS "$SRC/tests/gen_samples.c" -o "$OUT/gen_samples" -lm
echo "gen_samples built: $OUT/gen_samples (run to generate /tmp/*.wav)"

# Build GDExtension libraries using zig if available
if command -v "$ZIG" >/dev/null 2>&1; then
    echo "=== Building GDExtensions with zig ==="
    GD_OUT="$ROOT/addons/audio_gen/bin"
    mkdir -p "$GD_OUT"
    GDE_SRC="$SRC/gdext/audio_gen_gde.c"
    compile() {
        target="$1"; dest="$2"; shift 2
        echo "--- $target -> $(basename "$dest")"
        if timeout 90 "$ZIG" cc -target "$target" -std=c11 -O2 -shared -fPIC -fvisibility=hidden -I "$INCLUDE" -I "$SRC/../scene_score" "$@" -o "$dest" $SRCS "$GDE_SRC" -lm 2>&1 | tail -n 20; then
            return 0
        fi
        echo "FAILED $target"
        rm -f "$dest"
        return 1
    }
    ok=0; fail=0
    try() { if compile "$@"; then ok=$((ok+1)); else fail=$((fail+1)); fi; }
    try x86_64-linux-gnu.2.31 "$GD_OUT/libaudio_gen.linux.x86_64.so"
    try x86_64-windows-gnu "$GD_OUT/audio_gen.windows.x86_64.dll"
    try x86_64-macos "$GD_OUT/libaudio_gen.macos.x86_64.dylib" -mmacos-version-min=11.0
    try aarch64-macos "$GD_OUT/libaudio_gen.macos.arm64.dylib" -mmacos-version-min=11.0
    echo "GDExt built ok=$ok fail=$fail"
    ls -lh "$GD_OUT" || true
else
    echo "zig not found, skipping GDExtension builds (host tests already built)"
fi

echo "Done"

#!/usr/bin/env bash
# Rendered verification of the Sprite3DQuad Y-billboard shader. Needs a
# rasterizer: runs Godot as a Wayland client under sway headless with the
# pixman compositor renderer and Mesa llvmpipe software GL. Skips (exit 0)
# when sway is not installed - CI covers the math in motion_director_test.sh.
#
# Usage: tests/render_billboard_test.sh
#        GODOT_BIN=/path/to/godot tests/render_billboard_test.sh
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/home/user/tools/godot}"
if [ ! -x "$GODOT_BIN" ]; then
	echo "SKIP: Godot binary not found at $GODOT_BIN"
	exit 0
fi
if ! command -v sway >/dev/null 2>&1; then
	echo "SKIP: sway is not installed; no rasterizer for the billboard render test."
	exit 0
fi

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg}"
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
STARTED_SWAY=0
if [ ! -S "$XDG_RUNTIME_DIR/wayland-1" ]; then
	WLR_BACKENDS=headless WLR_RENDERER=pixman sway --unsupported-gpu >/tmp/sway.log 2>&1 &
	STARTED_SWAY=1
	for i in $(seq 1 50); do
		[ -S "$XDG_RUNTIME_DIR/wayland-1" ] && break
		sleep 0.2
	done
fi
if [ ! -S "$XDG_RUNTIME_DIR/wayland-1" ]; then
	echo "SKIP: could not start sway headless."
	exit 0
fi

cd "$ROOT"
OUT="$(mktemp -d)"
WAYLAND_DISPLAY=wayland-1 LIBGL_ALWAYS_SOFTWARE=1 timeout 120 "$GODOT_BIN" --path . \
	--rendering-driver opengl3 --display-driver wayland \
	res://tests/render_billboard_test.tscn -- "out=$OUT" 2>&1 | tee /tmp/billboard-render.log
rc=0
grep -q "BILLBOARD RENDER TEST: PASS" /tmp/billboard-render.log || rc=1
[ "$STARTED_SWAY" = 1 ] && pkill -x sway || true
if [ $rc -ne 0 ]; then
	echo "ERROR: billboard render test failed. Frames in $OUT"
	exit 1
fi
echo "OK: billboard render test passed. Frames in $OUT"

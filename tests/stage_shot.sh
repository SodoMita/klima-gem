#!/usr/bin/env bash
# Rendered verification of the Klima Gem show: boots the real main scene
# under sway headless (pixman compositor + Mesa llvmpipe software GL), plays
# the show like a player, and saves a screenshot at every production beat to
# tests/render_samples/stage/. Skips (exit 0) when sway is not installed, so
# CI without a rasterizer stays green.
#
# Usage: tests/stage_shot.sh
#        GODOT_BIN=/path/to/godot tests/stage_shot.sh
set -e
ROOT="$(cd "$(dirname "$0")/..")"
GODOT_BIN="${GODOT_BIN:-/home/user/.local/bin/godot}"
if [ ! -x "$GODOT_BIN" ]; then
	echo "SKIP: Godot binary not found at $GODOT_BIN"
	exit 0
fi
if ! command -v sway >/dev/null 2>&1; then
	echo "SKIP: sway is not installed; no rasterizer for the show render test."
	exit 0
fi

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg}"
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
STARTED_SWAY=0
if ! ls "$XDG_RUNTIME_DIR"/wayland-1 >/dev/null 2>&1; then
	WLR_BACKENDS=headless WLR_RENDERER=pixman sway --unsupported-gpu >/tmp/sway-show.log 2>&1 &
	STARTED_SWAY=1
	for i in $(seq 1 50); do
		ls "$XDG_RUNTIME_DIR"/wayland-1 >/dev/null 2>&1 && break
		sleep 0.2
	done
fi
if ! ls "$XDG_RUNTIME_DIR"/wayland-1 >/dev/null 2>&1; then
	echo "SKIP: could not start sway headless."
	[ "$STARTED_SWAY" = 1 ] && pkill -x sway || true
	exit 0
fi

cd "$ROOT"
rm -rf tests/render_samples/stage
WAYLAND_DISPLAY=wayland-1 LIBGL_ALWAYS_SOFTWARE=1 timeout 420 "$GODOT_BIN" --path . \
	--rendering-driver opengl3 --display-driver wayland \
	res://tests/stage_shot.tscn 2>&1 | tee /tmp/stage-shot.log
rc=0
grep -q "STAGE SHOT: PASS" /tmp/stage-shot.log || rc=1
[ "$STARTED_SWAY" = 1 ] && pkill -x sway || true
if [ $rc -ne 0 ]; then
	echo "ERROR: show render test failed. Log in /tmp/stage-shot.log"
	exit 1
fi
echo "OK: show render test passed. Shots in tests/render_samples/stage/"

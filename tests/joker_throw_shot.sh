#!/usr/bin/env bash
# Fair-throw + authored-stage check. Renders under sway headless if present.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/home/user/.local/bin/godot}"
cd "$ROOT"
"$GODOT_BIN" --headless --path . --import >/dev/null 2>&1 || true
if command -v sway >/dev/null 2>&1; then
	export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg}"; mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
	if ! ls "$XDG_RUNTIME_DIR"/wayland-1 >/dev/null 2>&1; then
		WLR_BACKENDS=headless WLR_RENDERER=pixman sway --unsupported-gpu >/tmp/sway-joker.log 2>&1 &
		for i in $(seq 1 50); do ls "$XDG_RUNTIME_DIR"/wayland-1 >/dev/null 2>&1 && break; sleep 0.2; done
	fi
	WAYLAND_DISPLAY=wayland-1 LIBGL_ALWAYS_SOFTWARE=1 timeout 400 "$GODOT_BIN" --path . --rendering-driver opengl3 --display-driver wayland --resolution 1280x720 res://tests/joker_throw_shot.tscn 2>&1 | tee /tmp/joker-throw.log
else
	timeout 400 "$GODOT_BIN" --headless --path . res://tests/joker_throw_shot.tscn 2>&1 | tee /tmp/joker-throw.log
fi
grep -q "JOKER THROW: PASS" /tmp/joker-throw.log

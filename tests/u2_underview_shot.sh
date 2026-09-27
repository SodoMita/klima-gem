#!/usr/bin/env bash
# Renders the under-view reveal under sway headless (pixman + llvmpipe).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; GODOT_BIN="${GODOT_BIN:-/home/user/.local/bin/godot}"
command -v sway >/dev/null 2>&1 || { echo "SKIP: no sway"; exit 0; }
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg}"; mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
ls "$XDG_RUNTIME_DIR"/wayland-1 >/dev/null 2>&1 || { WLR_BACKENDS=headless WLR_RENDERER=pixman sway --unsupported-gpu >/tmp/sway-u2.log 2>&1 & for i in $(seq 1 50); do ls "$XDG_RUNTIME_DIR"/wayland-1 >/dev/null 2>&1 && break; sleep 0.2; done; }
cd "$ROOT"
WAYLAND_DISPLAY=wayland-1 LIBGL_ALWAYS_SOFTWARE=1 timeout 240 "$GODOT_BIN" --path . --rendering-driver opengl3 --display-driver wayland --resolution 1280x720 res://tests/u2_underview_shot.tscn 2>&1 | tee /tmp/u2-shot.log
grep -q "U2 SHOT: PASS" /tmp/u2-shot.log

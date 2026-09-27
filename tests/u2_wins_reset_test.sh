#!/usr/bin/env bash
# Win count must travel with the backlog entry (human report: jumping to the
# previous/next choice left the wins behind).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; GODOT_BIN="${GODOT_BIN:-/home/user/.local/bin/godot}"
cd "$ROOT"
timeout 200 "$GODOT_BIN" --headless --path . res://tests/u2_wins_reset_test.tscn 2>&1 | tee /tmp/u2-wins.log
grep -q "U2 WINS RESET: PASS" /tmp/u2-wins.log

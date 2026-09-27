#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/home/user/.local/bin/godot}"
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT
cd "$ROOT"
timeout 30 "$GODOT_BIN" --headless res://tests/show_async_state_test.tscn 2>&1 | tee "$LOG"
grep -q 'ASYNC STATE TESTS: PASS' "$LOG"
! grep -qE 'SCRIPT ERROR|Parse Error|ASYNC STATE TESTS: FAIL' "$LOG"

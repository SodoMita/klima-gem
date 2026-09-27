#!/usr/bin/env bash
# Regression tests for the five defects reported on the Klima Gem show:
# physics (not tween) throw, words welded to gem facets, escaped dialogue
# colons, one portrait on the stage and the stage framing. Exits non-zero on
# failure so it can run in CI.
#
# Usage: tests/stage_integrity_test.sh
#        GODOT_BIN=/path/to/godot tests/stage_integrity_test.sh
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/home/user/.local/bin/godot}"
if [ ! -x "$GODOT_BIN" ]; then
	echo "ERROR: Godot binary not found at $GODOT_BIN"
	echo "       Set GODOT_BIN env var to the path of Godot 4.7+"
	exit 1
fi
cd "$ROOT"

echo "=== Klima Gem stage integrity tests ==="
"$GODOT_BIN" --headless res://tests/stage_integrity_test.tscn 2>&1 | tee /tmp/chrono-nexus-integrity.log
if ! grep -q "STAGE INTEGRITY TESTS: PASS" /tmp/chrono-nexus-integrity.log; then
	echo "ERROR: stage integrity tests failed. See /tmp/chrono-nexus-integrity.log"
	exit 1
fi
if grep -qE "^SCRIPT ERROR|Parse Error|Parse error" /tmp/chrono-nexus-integrity.log; then
	echo "ERROR: script errors while running the stage integrity tests."
	grep -E "^SCRIPT ERROR|Parse Error|Parse error" /tmp/chrono-nexus-integrity.log | head -5
	exit 1
fi
echo "OK: stage integrity tests passed."

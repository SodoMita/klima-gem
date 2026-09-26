#!/usr/bin/env bash
# Headless test for the StageDirector motion system (tweens, NLA tracks,
# frame ranges, shake, rollback replay). Exits non-zero on any failure so
# it can run in CI.
#
# Usage: tests/motion_director_test.sh
#        GODOT_BIN=/path/to/godot tests/motion_director_test.sh
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/home/user/.local/bin/godot}"
if [ ! -x "$GODOT_BIN" ]; then
	echo "ERROR: Godot binary not found at $GODOT_BIN"
	echo "       Set GODOT_BIN env var to the path of Godot 4.7+"
	exit 1
fi
cd "$ROOT"

echo "=== StageDirector motion tests ==="
"$GODOT_BIN" --headless res://tests/motion_director_test.tscn 2>&1 | tee /tmp/chrono-nexus-motion.log
if ! grep -q "MOTION TESTS: PASS" /tmp/chrono-nexus-motion.log; then
	echo "ERROR: StageDirector motion tests failed. See /tmp/chrono-nexus-motion.log"
	exit 1
fi
if grep -q "MOTION TESTS: FAIL" /tmp/chrono-nexus-motion.log; then
	echo "ERROR: StageDirector motion tests reported failures."
	exit 1
fi
echo "OK: StageDirector motion tests passed."

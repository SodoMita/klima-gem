#!/usr/bin/env bash
# Headless test for the dubstep audio: C generator through the AudioGen
# extension, the AudioDirector stage-music path, the event sound bank and
# gem collision sounds.
#
# Usage: tests/dubstep_audio_test.sh
#        GODOT_BIN=/path/to/godot tests/dubstep_audio_test.sh
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/home/user/.local/bin/godot}"
if [ ! -x "$GODOT_BIN" ]; then
	echo "ERROR: Godot binary not found at $GODOT_BIN"
	echo "       Set GODOT_BIN env var to the path of Godot 4.7+"
	exit 1
fi
cd "$ROOT"

echo "=== Dubstep audio tests ==="
"$GODOT_BIN" --headless res://tests/dubstep_audio_test.tscn 2>&1 | tee /tmp/klima-dubstep-audio.log
if ! grep -q "DUBSTEP AUDIO TESTS: PASS" /tmp/klima-dubstep-audio.log; then
	echo "ERROR: dubstep audio tests failed. See /tmp/klima-dubstep-audio.log"
	exit 1
fi
echo "Dubstep audio tests passed."

#!/usr/bin/env bash
# Joker's stage + throw suites: the authored .tscn set, the lifted closed
# glass case, the crown/table gem labels, persistent modifications, and the
# physics fairness of the throw (24 solo throws must spread over the faces).
#
# Usage: tests/joker_stage_test.sh
#        GODOT_BIN=/path/to/godot tests/joker_stage_test.sh
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/home/user/.local/bin/godot}"
if [ ! -x "$GODOT_BIN" ]; then
	echo "ERROR: Godot binary not found at $GODOT_BIN"
	echo "       Set GODOT_BIN env var to the path of Godot 4.7+"
	exit 1
fi
cd "$ROOT"
timeout 180 "$GODOT_BIN" --headless --path . --import >/tmp/godot-import.log 2>&1 || true

for scene in joker_stage_test joker_throw_test; do
	echo "=== ${scene} ==="
	"$GODOT_BIN" --headless --path . "res://tests/${scene}.tscn" 2>&1 | tee "/tmp/${scene}.log"
	if grep -qE "^FAIL|, [1-9][0-9]* failed" "/tmp/${scene}.log"; then
		echo "ERROR: ${scene} reported failures. See /tmp/${scene}.log"
		exit 1
	fi
	if ! grep -q "0 failed" "/tmp/${scene}.log"; then
		echo "ERROR: ${scene} did not finish. See /tmp/${scene}.log"
		exit 1
	fi
done
echo "OK: Joker stage and throw tests passed."

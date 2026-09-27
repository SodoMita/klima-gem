#!/usr/bin/env bash
# MultiMesh sanity regression test: the star cloth / audience / glowstick
# buffers in the show stage must never serialize garbage transforms again
# (the "exploded 3D scene" bug). Exits non-zero on failure.
#
# Usage: tests/multimesh_sanity_test.sh
#        GODOT_BIN=/path/to/godot tests/multimesh_sanity_test.sh
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/home/user/.local/bin/godot}"
if [ ! -x "$GODOT_BIN" ]; then
	GODOT_BIN="$(command -v godot || true)"
fi
if [ ! -x "$GODOT_BIN" ]; then
	echo "ERROR: Godot binary not found; set GODOT_BIN"
	exit 1
fi
cd "$ROOT"
timeout 120 "$GODOT_BIN" --headless --path . --editor --quit >/tmp/godot-import.log 2>&1 || true

echo "=== MultiMesh sanity tests ==="
"$GODOT_BIN" --headless res://tests/multimesh_sanity_test.tscn 2>&1 | tee /tmp/klima-gem-multimesh.log
if ! grep -q "MULTIMESH TESTS: PASS" /tmp/klima-gem-multimesh.log; then
	echo "ERROR: MultiMesh sanity tests failed. See /tmp/klima-gem-multimesh.log"
	exit 1
fi

#!/usr/bin/env bash
# Headless test for the Klima Gem show: gems, edge tables, the throw
# ceremony, trials, star bookkeeping, restore re-dressing, and a full
# seeded playthrough of the show dialogue. Exits non-zero on failure so
# it can run in CI.
#
# Usage: tests/show_stage_test.sh
#        GODOT_BIN=/path/to/godot tests/show_stage_test.sh
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/home/user/.local/bin/godot}"
if [ ! -x "$GODOT_BIN" ]; then
	echo "ERROR: Godot binary not found at $GODOT_BIN"
	echo "       Set GODOT_BIN env var to the path of Godot 4.7+"
	exit 1
fi
cd "$ROOT"

echo "=== Klima Gem show tests ==="
"$GODOT_BIN" --headless res://tests/show_stage_test.tscn 2>&1 | tee /tmp/chrono-nexus-show.log
if ! grep -q "SHOW TESTS: PASS" /tmp/chrono-nexus-show.log; then
	echo "ERROR: Klima Gem show tests failed. See /tmp/chrono-nexus-show.log"
	exit 1
fi
if grep -q "SHOW TESTS: FAIL" /tmp/chrono-nexus-show.log; then
	echo "ERROR: Klima Gem show tests reported failures."
	exit 1
fi
if grep -qE "^SCRIPT ERROR|Parse Error|Parse error" /tmp/chrono-nexus-show.log; then
	echo "ERROR: script errors while running the show tests."
	grep -E "^SCRIPT ERROR|Parse Error|Parse error" /tmp/chrono-nexus-show.log | head -5
	exit 1
fi
echo "OK: Klima Gem show tests passed."

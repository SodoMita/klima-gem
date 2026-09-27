#!/usr/bin/env bash
# Case-specific transformation cards and same-frame rollback regression.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/home/user/.local/bin/godot}"
cd "$ROOT"
timeout 180 "$GODOT_BIN" --headless --path . --import >/tmp/mod-card-import.log 2>&1
timeout 90 "$GODOT_BIN" --headless --path . res://tests/mod_card_test.tscn 2>&1 | tee /tmp/mod-card-test.log
if grep -qE '^SCRIPT ERROR|^ERROR|Parse Error|Parse error' /tmp/mod-card-test.log || ! grep -q 'MOD CARD TESTS: PASS' /tmp/mod-card-test.log; then
	echo "ERROR: Modification card regression failed. See /tmp/mod-card-test.log"
	exit 1
fi
echo 'OK: modification card regression passed.'

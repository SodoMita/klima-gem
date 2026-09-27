#!/usr/bin/env bash
# The body-part gem must be readable on Aurora: every part x mod pair changes
# her, inside the region the gem named, and no two pairs look the same.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/home/user/.local/bin/godot}"
cd "$ROOT"
timeout 300 "$GODOT_BIN" --headless --path . --import >/tmp/aurora-part-import.log 2>&1
timeout 600 "$GODOT_BIN" --headless --path . res://tests/aurora_part_mods_test.tscn 2>&1 | tee /tmp/aurora-part-mods-test.log
if grep -qE '^SCRIPT ERROR|^ERROR|Parse Error|Parse error' /tmp/aurora-part-mods-test.log || ! grep -q 'AURORA PART MODS: PASS' /tmp/aurora-part-mods-test.log; then
	echo 'ERROR: per-body-part sprite regression failed.'
	exit 1
fi
echo 'OK: Aurora responds to the body-part gem.'

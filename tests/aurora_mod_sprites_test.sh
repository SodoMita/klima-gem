#!/usr/bin/env bash
# Full-body Aurora image variants: lossless WebP, alpha, expression and rewind.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/home/user/.local/bin/godot}"
cd "$ROOT"
python3 - <<'PY'
from pathlib import Path
variants = sorted(Path('assets/characters/mods').glob('*.webp'))
assert len(variants) == 45, f'expected 5 expressions x 9 shifts; got {len(variants)}'
for p in variants:
    data = p.read_bytes()
    assert data[:4] == b'RIFF' and data[8:12] == b'WEBP' and b'VP8L' in data[:128], f'not packed lossless WebP: {p}'
print('OK: 45 packed lossless WebP character sprites')
PY
timeout 180 "$GODOT_BIN" --headless --path . --import >/tmp/aurora-mod-import.log 2>&1
timeout 120 "$GODOT_BIN" --headless --path . res://tests/aurora_mod_sprites_test.tscn 2>&1 | tee /tmp/aurora-mod-sprites-test.log
if grep -qE '^SCRIPT ERROR|^ERROR|Parse Error|Parse error' /tmp/aurora-mod-sprites-test.log || ! grep -q 'AURORA MOD SPRITES: PASS' /tmp/aurora-mod-sprites-test.log; then
	echo 'ERROR: transformed character sprite regression failed.'
	exit 1
fi
echo 'OK: transformed Aurora sprites passed.'

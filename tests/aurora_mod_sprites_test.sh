#!/usr/bin/env bash
# Fresh modular Aurora art: nine semantic layers, lossless WebP, no old plates.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/home/user/.local/bin/godot}"
cd "$ROOT"
python3 - <<'PY'
from pathlib import Path
root = Path('assets/characters/parts/aurora')
static = sorted(p for p in root.glob('*.webp'))
expressions = sorted((root / 'expressions').glob('*/*.webp'))
expected_static = {'back.webp', 'legs.webp', 'skin.webp', 'milk.webp', 'heart.webp', 'hair.webp', 'hands.webp'}
assert {p.name for p in static} == expected_static, f'static layer mismatch: {static}'
assert len(expressions) == 10, f'expected 5 expressions x EYES/VOICE; got {len(expressions)}'
assert not list(root.rglob('*.png')), 'modular body must never contain PNG files'
assert not Path('assets/characters/mods').exists(), 'legacy full-body combination plates still exist'
for p in static + expressions:
    data = p.read_bytes()
    assert data[:4] == b'RIFF' and data[8:12] == b'WEBP' and b'VP8L' in data[:128], f'not packed lossless WebP: {p}'
source = Path('tools/draw_aurora_body_parts.py').read_text()
assert 'Image.open' not in source, 'part generator must not read/slice an old portrait'
assert 'parts/aurora' in source.replace('" / "', '/'), 'generator output contract changed unexpectedly'
print('OK: 9 direct-drawn semantic layers, 5 eye/mouth expression redraws, VP8L only')
PY
timeout 180 "$GODOT_BIN" --headless --path . --import >/tmp/aurora-mod-import.log 2>&1
timeout 120 "$GODOT_BIN" --headless --path . res://tests/aurora_mod_sprites_test.tscn 2>&1 | tee /tmp/aurora-mod-sprites-test.log
if grep -qE '^SCRIPT ERROR|^ERROR|Parse Error|Parse error' /tmp/aurora-mod-sprites-test.log || ! grep -q 'AURORA MODULAR BODY: PASS' /tmp/aurora-mod-sprites-test.log; then
	echo 'ERROR: modular Aurora body regression failed.'
	exit 1
fi
echo 'OK: modular Aurora body passed all 9x9 local-response checks.'

#!/usr/bin/env bash
# Body-part sprite layers: aligned lossless WebP art + per-part rig behavior.
set -e
ROOT="$(cd "$(dirname "$0")/.."; pwd)"
GODOT_BIN="${GODOT_BIN:-/home/user/.local/bin/godot}"
cd "$ROOT"
python3 - <<'PY'
from pathlib import Path
from PIL import Image

parts = {"back", "legs", "skin", "hair", "milk", "hands", "eyes", "voice", "heart"}
variants = [f"{part}_{expr}" for part in ("eyes", "voice")
            for expr in ("happy", "sad", "serious", "surprised", "gorgeous")]
files = sorted(p.stem for p in Path("assets/characters/parts").glob("*.webp"))
assert set(files) == parts | set(variants), f"part art drifted: {files}"
size = None
for f in Path("assets/characters/parts").glob("*.webp"):
    data = f.read_bytes()
    assert data[:4] == b"RIFF" and data[8:12] == b"WEBP" and b"VP8L" in data[:128], f"not packed lossless WebP: {f}"
    im = Image.open(f).convert("RGBA")
    size = size or im.size
    assert im.size == size, f"layers must share one canvas: {f}"
    assert im.getpixel((0, 0))[3] == 0 and im.getpixel((im.width - 1, im.height - 1))[3] == 0, f"not transparent: {f}"
for p in parts:
    im = Image.open(f"assets/characters/parts/{p}.webp").convert("RGBA")
    alpha = im.getchannel("A")
    assert alpha.getbbox() is not None, f"empty layer: {p}"
print(f"OK: 9 aligned part layers (+{len(variants)} expression variants), packed lossless WebP")

import json
meta = json.loads(Path("assets/characters/parts/parts.json").read_text())
assert set(meta["parts"].keys()) == {p.upper() for p in parts}, "parts.json must describe all nine parts"
for name, part in meta["parts"].items():
    px, py = part["pivot"]
    assert 0.0 <= px <= 1.0 and 0.0 <= py <= 1.0, f"pivot out of canvas: {name}"
zs = [part["z"] for part in meta["parts"].values()]
assert len(set(zs)) == 9, "z order must be unique"
print("OK: parts.json pivots and z-order sane")
PY
timeout 180 "$GODOT_BIN" --headless --path . --import >/tmp/aurora-parts-import.log 2>&1
timeout 120 "$GODOT_BIN" --headless --path . res://tests/aurora_parts_rig_test.tscn 2>&1 | tee /tmp/aurora-parts-rig-test.log
if grep -qE '^SCRIPT ERROR|^ERROR|Parse Error|Parse error' /tmp/aurora-parts-rig-test.log || ! grep -q 'AURORA PARTS RIG: PASS' /tmp/aurora-parts-rig-test.log; then
	echo 'ERROR: body-part rig regression failed.'
	exit 1
fi
echo 'OK: layered body-part rig passed.'

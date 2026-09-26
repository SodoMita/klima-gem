#!/usr/bin/env python3
"""Copy a straight-alpha sprite into the runtime slots. Refuses to overwrite.

    python3 tools/install_sprite.py path/to/aurora.png --id aurora --expression neutral
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from sprite_pipeline.cast import ROOT, find, load  # noqa: E402


def install(src: Path, cid: str, expression: str, *, assets_dir: Path, sprites_dir: Path) -> Path:
    if not src.exists():
        raise SystemExit(f"not found: {src}")
    filename = f"{cid}_{expression}.webp"
    for folder in (assets_dir, sprites_dir):
        target = folder / filename
        if target.exists():
            raise SystemExit(f"refusing to overwrite {target}")
    _write_webp(src, assets_dir / filename)
    _write_webp(src, sprites_dir / filename)
    return assets_dir / filename


def _write_webp(src: Path, dest: Path) -> None:
    try:
        from PIL import Image
    except ImportError as exc:
        raise SystemExit("Pillow required: pip install -r tools/requirements.txt") from exc
    dest.parent.mkdir(parents=True, exist_ok=True)
    Image.open(src).convert("RGBA").save(dest, "WEBP", lossless=True)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("src")
    ap.add_argument("--id", required=True)
    ap.add_argument("--expression", required=True)
    args = ap.parse_args()
    doc = load()
    find(doc, args.id)
    if args.expression not in doc["expressions"]:
        raise SystemExit(f"unknown expression {args.expression!r}")
    dest = install(
        Path(args.src),
        args.id,
        args.expression,
        assets_dir=ROOT / "assets" / "characters",
        sprites_dir=ROOT / "Sprites",
    )
    print(f"wrote {dest}")
    print(f'add balloon key "{args.id}_{args.expression}"')
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

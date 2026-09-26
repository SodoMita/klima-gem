#!/usr/bin/env python3
"""Composite an RGBA sprite onto a base image. Not a matte checker.

Ported from the Seirin sprite pipeline (SodoMita/Seirin) for Chrono Nexus.
"""
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


def composite(base_path: Path, overlay_path: Path, out_path: Path) -> None:
    base = Image.open(base_path).convert("RGBA")
    overlay = Image.open(overlay_path).convert("RGBA")
    if base.size != overlay.size:
        overlay = overlay.resize(base.size, Image.Resampling.LANCZOS)
    out = base.copy()
    out.alpha_composite(overlay)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out.save(out_path)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("base")
    ap.add_argument("overlay")
    ap.add_argument("output")
    args = ap.parse_args()
    composite(Path(args.base), Path(args.overlay), Path(args.output))


if __name__ == "__main__":
    main()

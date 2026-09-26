#!/usr/bin/env python3
"""Triangulate a white/black sheet pair and slice column groups into sprites.

Ported from the Seirin sprite pipeline (SodoMita/Seirin) for Chrono Nexus.
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image


def triangulate(white_path: Path, black_path: Path) -> tuple[Image.Image, Image.Image]:
    white = Image.open(white_path).convert("RGB")
    black = Image.open(black_path).convert("RGB")
    if white.size != black.size:
        raise SystemExit(f"Size mismatch: white={white.size}, black={black.size}")

    w = np.asarray(white, dtype=np.float32) / 255.0
    b = np.asarray(black, dtype=np.float32) / 255.0

    alpha_rgb = 1.0 - (w - b)
    alpha = np.clip(alpha_rgb.mean(axis=2), 0.0, 1.0)
    safe_alpha = np.maximum(alpha, 1e-6)
    fg = np.clip(b / safe_alpha[..., None], 0.0, 1.0)

    rgba = np.dstack([
        (fg * 255.0 + 0.5).astype(np.uint8),
        (alpha * 255.0 + 0.5).astype(np.uint8),
    ])
    rgba_img = Image.fromarray(rgba, "RGBA")
    alpha_img = Image.fromarray((alpha * 255.0 + 0.5).astype(np.uint8), "L")
    return rgba_img, alpha_img


def column_groups(alpha_im: Image.Image, min_pixels: int = 12) -> list[tuple[int, int]]:
    w, h = alpha_im.size
    alpha = alpha_im.getchannel("A")
    cols = []
    for x in range(w):
        count = 0
        for y in range(h):
            if alpha.getpixel((x, y)) > 15:
                count += 1
        cols.append(count)

    groups: list[tuple[int, int]] = []
    start = None
    for x, count in enumerate(cols):
        if count >= min_pixels and start is None:
            start = x
        elif count < min_pixels and start is not None:
            if x - start > 20:
                groups.append((start, x - 1))
            start = None
    if start is not None:
        groups.append((start, w - 1))
    return groups


def crop_bbox(im: Image.Image, x0: int, x1: int, pad: int = 8) -> Image.Image:
    alpha = im.getchannel("A")
    w, h = im.size
    top = h
    bottom = 0
    left = x1
    right = x0
    for x in range(max(0, x0), min(w, x1 + 1)):
        for y in range(h):
            if alpha.getpixel((x, y)) > 15:
                top = min(top, y)
                bottom = max(bottom, y)
                left = min(left, x)
                right = max(right, x)
    left = max(0, left - pad)
    right = min(w, right + pad)
    top = max(0, top - pad)
    bottom = min(h, bottom + pad)
    return im.crop((left, top, right + 1, bottom + 1))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("white")
    ap.add_argument("black")
    ap.add_argument("rgba_out")
    ap.add_argument("--alpha-out")
    ap.add_argument("--dest-dir")
    ap.add_argument("--names", nargs="*")
    args = ap.parse_args()

    rgba, alpha = triangulate(Path(args.white), Path(args.black))
    rgba_path = Path(args.rgba_out)
    rgba_path.parent.mkdir(parents=True, exist_ok=True)
    rgba.save(rgba_path)
    if args.alpha_out:
        alpha_path = Path(args.alpha_out)
        alpha_path.parent.mkdir(parents=True, exist_ok=True)
        alpha.save(alpha_path)

    if args.dest_dir and args.names:
        dest_dir = Path(args.dest_dir)
        dest_dir.mkdir(parents=True, exist_ok=True)
        groups = [g for g in column_groups(rgba) if (g[1] - g[0] + 1) >= 40]
        names = list(args.names)
        if len(groups) > len(names):
            groups = sorted(sorted(groups, key=lambda g: g[1] - g[0], reverse=True)[: len(names)])
        if len(groups) != len(names):
            raise SystemExit(f"Expected {len(names)} groups, found {len(groups)}")
        for (x0, x1), name in zip(groups, names):
            sprite = crop_bbox(rgba, x0, x1)
            sprite.save(dest_dir / f"{name}.png")


if __name__ == "__main__":
    main()


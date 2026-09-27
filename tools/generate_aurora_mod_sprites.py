#!/usr/bin/env python3
"""Build stage-ready transformation portraits from Aurora's own expression art.

The source images, silhouette, face and pose stay Aurora's. The generated
highlights sit on her body, never in a separate icon/card. For reproducibility:

    python3 tools/generate_aurora_mod_sprites.py [--expression serious]

Output is lossless RGBA WebP (VP8L), NOT screenshots, under
assets/characters/mods/. Use the existing facial expression as the filename
prefix so the show can change mood without dropping a transformation.
"""
from __future__ import annotations

import argparse
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "characters"
DEST = SOURCE / "mods"
EXPRESSIONS = ("serious", "surprised", "sad", "happy", "gorgeous")
MODS = ("giant", "tiny", "sticky", "bouncy", "glass", "magnet", "heavy", "glowing", "mega")
PALETTE = {
    "giant": (255, 211, 91), "tiny": (153, 225, 255),
    "sticky": (117, 240, 169), "bouncy": (255, 169, 106),
    "glass": (180, 238, 255), "magnet": (204, 150, 255),
    "heavy": (158, 166, 205), "glowing": (102, 250, 240),
    "mega": (255, 167, 139),
}


def scaled(w: int, h: int, x: float, y: float) -> tuple[int, int]:
    return round(w * x), round(h * y)


def rect(w: int, h: int, cx: float, cy: float, rx: float, ry: float) -> tuple[int, int, int, int]:
    x0, y0 = scaled(w, h, cx - rx, cy - ry)
    x1, y1 = scaled(w, h, cx + rx, cy + ry)
    return x0, y0, x1, y1


def make_aura(src: Image.Image, color: tuple[int, int, int], power: float) -> Image.Image:
    """Glow OUTSIDE the original silhouette so the face never gets repainted."""
    w, _ = src.size
    alpha = src.getchannel("A")
    r = max(3, round(w * 0.023))
    outer = alpha.filter(ImageFilter.MaxFilter(2 * r + 1))
    blur = outer.filter(ImageFilter.GaussianBlur(r * 2))
    halo = ImageChops.subtract(blur, alpha)
    halo = halo.point(lambda v: round(v * power))
    layer = Image.new("RGBA", src.size, (*color, 0))
    layer.putalpha(halo)
    return Image.alpha_composite(layer, src)


def wash_limb(src: Image.Image, color: tuple[int, int, int], amount: float, regions: tuple[tuple[float, float, float, float], ...], translucent: bool = False) -> Image.Image:
    """Soft body-localized tint; facial pixels outside the regions are unchanged."""
    arr = np.asarray(src, dtype=np.float32).copy()
    h, w = arr.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    mask = np.zeros((h, w), dtype=np.float32)
    for x, y, rx, ry in regions:
        distance = ((xx / w - x) / rx) ** 2 + ((yy / h - y) / ry) ** 2
        mask = np.maximum(mask, np.exp(-2.4 * distance))
    mask *= amount
    arr[:, :, :3] = arr[:, :, :3] * (1 - mask[:, :, None]) + np.asarray(color)[None, None, :] * mask[:, :, None]
    if translucent:
        arr[:, :, 3] *= 1 - mask * 0.43
    return Image.fromarray(np.uint8(np.clip(arr + 0.5, 0, 255)), "RGBA")


def shine_lines(src: Image.Image, mod: str) -> Image.Image:
    """Draw small mod-specific effects on Aurora's hands, legs and clothing."""
    w, h = src.size
    color = PALETTE[mod]
    effects = Image.new("RGBA", src.size)
    d = ImageDraw.Draw(effects)
    thick = max(2, round(w * 0.009))
    p = lambda x, y: scaled(w, h, x, y)

    def loop(cx: float, cy: float, rx: float, ry: float, start: int = 0, end: int = 359, a: int = 195, width: int = thick) -> None:
        d.arc(rect(w, h, cx, cy, rx, ry), start, end, fill=(*color, a), width=width)

    def stroke(coords: list[tuple[float, float]], a: int = 175, width: int = thick) -> None:
        d.line([p(x, y) for x, y in coords], fill=(*color, a), width=width, joint="curve")

    def spark(x: float, y: float, radius: float = 0.012, a: int = 185) -> None:
        px, py = p(x, y)
        dx = round(radius * w)
        dy = round(radius * h)
        d.line([(px - dx, py), (px + dx, py)], fill=(*color, a), width=max(1, thick // 2))
        d.line([(px, py - dy), (px, py + dy)], fill=(*color, a), width=max(1, thick // 2))

    if mod in ("giant", "mega"):
        # Gauntlets and raised shoulder auras amplify HER hands and stature.
        for hand_x in (0.18, 0.82):
            loop(hand_x, 0.59, 0.10, 0.075, 205, 500, 205, thick + 1)
            loop(hand_x, 0.54, 0.07, 0.045, 0, 359, 130)
        stroke([(0.13, 0.39), (0.08, 0.37), (0.07, 0.25), (0.16, 0.22)], 145)
        stroke([(0.87, 0.39), (0.92, 0.37), (0.93, 0.25), (0.84, 0.22)], 145)
        for x, y in ((0.10, 0.48), (0.90, 0.49), (0.30, 0.72), (0.70, 0.72)):
            spark(x, y)
        if mod == "mega":
            for x in (0.32, 0.5, 0.68):
                spark(x, 0.31, 0.025, 200)
            loop(0.5, 0.36, 0.24, 0.11, 15, 165, 165)
    elif mod == "tiny":
        # The body's runtime scale actually shrinks; these stars emphasize it.
        for x, y in ((0.15, 0.43), (0.85, 0.44), (0.23, 0.76), (0.78, 0.77), (0.50, 0.96)):
            spark(x, y, 0.012, 195)
        loop(0.5, 0.78, 0.30, 0.04, 0, 359, 120)
    elif mod == "sticky":
        # Translucent slime STRANDS follow Aurora's existing wrists/boots.
        for x, sgn in ((0.18, -1), (0.82, 1)):
            stroke([(x, 0.48), (x + 0.02 * sgn, 0.55), (x, 0.61), (x + 0.012 * sgn, 0.655)], 210, thick + 1)
            d.ellipse(rect(w, h, x + 0.012 * sgn, 0.660, 0.013, 0.010), fill=(*color, 170))
        for x in (0.4, 0.6):
            stroke([(x, 0.79), (x + 0.024, 0.86), (x + 0.01, 0.9)], 140)
    elif mod == "bouncy":
        # Warm spring coils near the knees and ankle kicks; same figure.
        for x in (0.39, 0.61):
            for y in (0.76, 0.80, 0.84):
                loop(x, y, 0.052, 0.017, 0, 359, 160)
        loop(0.5, 0.98, 0.34, 0.026, 195, 345, 165)
        for x in (0.18, 0.82):
            spark(x, 0.56, 0.016)
    elif mod == "glass":
        # Faceted lines on translucent forearms and shins, not over the face.
        for x, sign in ((0.2, 1), (0.8, -1)):
            stroke([(x, 0.49), (x + 0.025 * sign, 0.56), (x, 0.63)], 165)
            stroke([(x - 0.04 * sign, 0.55), (x + 0.02 * sign, 0.56)], 155)
        for x in (0.4, 0.6):
            stroke([(x, 0.68), (x - 0.045, 0.76), (x + 0.01, 0.83), (x - 0.02, 0.9)], 165)
            spark(x, 0.80, 0.012)
    elif mod == "magnet":
        # Magnetic flux around Aurora's hands and the suit's seams.
        for cx in (0.16, 0.84):
            loop(cx, 0.52, 0.10, 0.095, 25, 305, 175)
            loop(cx, 0.52, 0.14, 0.125, 195, 460, 100)
        for x, y in ((0.11, 0.45), (0.86, 0.44), (0.23, 0.61), (0.76, 0.62)):
            spark(x, y, 0.015)
    elif mod == "heavy":
        # Weighted plated suit on Aurora's legs/shoulders; no new prop.
        for x in (0.40, 0.60):
            d.polygon([p(x - 0.05, 0.68), p(x + 0.05, 0.68), p(x + 0.04, 0.73), p(x - 0.04, 0.74)], fill=(*color, 78))
            loop(x, 0.72, 0.06, 0.035, 15, 165, 165)
            loop(x, 0.95, 0.075, 0.028, 0, 359, 130)
        loop(0.50, 0.39, 0.21, 0.13, 20, 160, 110)
    elif mod == "glowing":
        # Bright energy runs through her own circuit suit and hair edges.
        loop(0.50, 0.38, 0.15, 0.095, 0, 359, 155)
        stroke([(0.5, 0.42), (0.49, 0.51), (0.40, 0.65), (0.39, 0.81)], 170)
        stroke([(0.5, 0.42), (0.51, 0.51), (0.60, 0.65), (0.61, 0.81)], 170)
        for x, y in ((0.15, 0.29), (0.87, 0.32), (0.13, 0.53), (0.87, 0.55), (0.45, 0.04)):
            spark(x, y, 0.016)

    soft = effects.filter(ImageFilter.GaussianBlur(max(2, w * 0.013)))
    soft.putalpha(soft.getchannel("A").point(lambda a: round(a * 0.49)))
    return Image.alpha_composite(Image.alpha_composite(src, soft), effects)


def generate(expression: str, mod: str) -> Image.Image:
    source = Image.open(SOURCE / f"aurora_{expression}.webp").convert("RGBA")
    w, h = source.size
    if source.getchannel("A").getextrema()[0] != 0:
        raise ValueError("Aurora source must have transparent pixels")
    color = PALETTE[mod]
    if mod == "glass":
        source = wash_limb(source, (170, 230, 252), 0.38, (
            (0.20, 0.54, 0.095, 0.15), (0.80, 0.54, 0.095, 0.15),
            (0.41, 0.80, 0.10, 0.17), (0.59, 0.80, 0.10, 0.17),
        ), translucent=True)
    elif mod == "heavy":
        source = wash_limb(source, (88, 104, 143), 0.24, ((0.5, 0.77, 0.30, 0.23),))
    elif mod == "glowing":
        source = wash_limb(source, (140, 255, 242), 0.20, ((0.5, 0.42, 0.33, 0.36),))
    elif mod in ("giant", "mega"):
        source = wash_limb(source, color, 0.15, ((0.15, 0.55, 0.11, 0.15), (0.85, 0.55, 0.11, 0.15)))

    power = {"tiny": 0.14, "heavy": 0.18, "glowing": 0.48, "mega": 0.38}.get(mod, 0.24)
    return shine_lines(make_aura(source, color, power), mod)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expression", choices=EXPRESSIONS, help="only generate one expression for inspection")
    args = parser.parse_args()
    DEST.mkdir(parents=True, exist_ok=True)
    for expression in (args.expression,) if args.expression else EXPRESSIONS:
        for mod in MODS:
            out = DEST / f"aurora_{expression}_{mod}.webp"
            im = generate(expression, mod)
            im.save(out, "WEBP", lossless=True, quality=100, method=6, exact=True)
            print(f"{out.relative_to(ROOT)}  {im.width}x{im.height} RGBA")


if __name__ == "__main__":
    main()

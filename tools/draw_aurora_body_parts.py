#!/usr/bin/env python3
"""Draw the Klima Gem show's modular Aurora placeholder from scratch.

This intentionally does not read, cut, mask, or sample any existing portrait.
Every visible body region is drawn directly onto its own transparent canvas so
an artist can replace one WebP at a time without changing runtime code.

Usage:
    python3 tools/draw_aurora_body_parts.py

Output is deterministic, lossless RGBA WebP under
assets/characters/parts/aurora/. PNG files are never produced.
"""
from __future__ import annotations

import argparse
from pathlib import Path
from typing import Callable

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "assets" / "characters" / "parts" / "aurora"
WIDTH, HEIGHT = 640, 960
EXPRESSIONS = ("serious", "surprised", "sad", "happy", "gorgeous")
PARTS = ("back", "legs", "body", "breast", "heart", "hair", "eyes", "voice", "hands")

# Aurora-inspired placeholder palette. These are authored constants, not
# sampled colors from the old full-body sprites.
INK = (39, 25, 72, 255)
HAIR_DARK = (72, 50, 139, 255)
HAIR_MID = (133, 91, 212, 255)
HAIR_LIGHT = (221, 157, 246, 255)
SKIN = (247, 191, 170, 255)
SKIN_SHADE = (221, 142, 139, 255)
SUIT_DARK = (36, 49, 99, 255)
SUIT_MID = (69, 101, 174, 255)
SUIT_LIGHT = (104, 219, 230, 255)
GEM = (255, 101, 194, 255)
WHITE = (255, 250, 253, 255)


def canvas() -> Image.Image:
    return Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))


def line(draw: ImageDraw.ImageDraw, points: list[tuple[int, int]], fill=INK, width=10) -> None:
    draw.line(points, fill=fill, width=width, joint="curve")


def draw_back() -> Image.Image:
    im = canvas()
    d = ImageDraw.Draw(im)
    # Back hair/cape: entirely behind the remaining layers.
    d.polygon([(222, 169), (180, 278), (176, 486), (128, 716), (235, 657),
               (318, 760), (402, 657), (516, 716), (464, 486), (461, 278),
               (418, 169)], fill=INK)
    d.polygon([(238, 178), (202, 292), (210, 491), (169, 668), (249, 620),
               (320, 710), (391, 620), (472, 668), (430, 491), (438, 292),
               (402, 178)], fill=HAIR_DARK)
    # Long luminous inner ribbons make BACK visually identifiable.
    line(d, [(245, 250), (225, 420), (207, 596)], HAIR_MID, 20)
    line(d, [(395, 250), (415, 420), (433, 596)], HAIR_MID, 20)
    line(d, [(320, 220), (320, 645)], HAIR_LIGHT, 11)
    return im


def draw_legs() -> Image.Image:
    im = canvas()
    d = ImageDraw.Draw(im)
    # Split hips and legs are one semantic LEGS layer.
    d.polygon([(238, 584), (313, 584), (305, 760), (277, 901), (191, 901),
               (223, 745)], fill=INK)
    d.polygon([(327, 584), (402, 584), (417, 745), (449, 901), (363, 901),
               (335, 760)], fill=INK)
    d.polygon([(247, 596), (302, 596), (295, 750), (270, 881), (210, 881),
               (236, 738)], fill=SUIT_MID)
    d.polygon([(338, 596), (393, 596), (404, 738), (430, 881), (370, 881),
               (345, 750)], fill=SUIT_MID)
    # Boots and cyan seam strips.
    d.rounded_rectangle((184, 862, 281, 918), radius=24, fill=INK)
    d.rounded_rectangle((359, 862, 456, 918), radius=24, fill=INK)
    line(d, [(261, 610), (252, 742), (229, 850)], SUIT_LIGHT, 13)
    line(d, [(379, 610), (388, 742), (411, 850)], SUIT_LIGHT, 13)
    return im


def draw_body() -> Image.Image:
    """Draw the head, neck and torso base, but never the breast panels."""
    im = canvas()
    d = ImageDraw.Draw(im)
    # Ears, neck and face; facial features live on EYES/VOICE layers.
    d.ellipse((183, 221, 239, 326), fill=INK)
    d.ellipse((401, 221, 457, 326), fill=INK)
    d.ellipse((194, 230, 231, 314), fill=SKIN_SHADE)
    d.ellipse((409, 230, 446, 314), fill=SKIN_SHADE)
    d.rounded_rectangle((220, 112, 420, 378), radius=91, fill=INK)
    d.rounded_rectangle((232, 124, 408, 366), radius=80, fill=SKIN)
    d.polygon([(280, 345), (360, 345), (372, 432), (268, 432)], fill=INK)
    d.polygon([(290, 350), (350, 350), (357, 424), (283, 424)], fill=SKIN)
    # Torso/bodice substrate is BODY. It deliberately has no paired breast
    # ellipses; those exist only in breast.webp and can transform alone.
    d.polygon([(254, 397), (386, 397), (440, 488), (407, 662), (233, 662),
               (200, 488)], fill=INK)
    d.polygon([(264, 414), (376, 414), (420, 495), (391, 642), (249, 642),
               (220, 495)], fill=SUIT_DARK)
    d.polygon([(254, 557), (386, 557), (376, 631), (264, 631)], fill=SUIT_MID)
    line(d, [(267, 610), (373, 610)], HAIR_LIGHT, 8)
    # Small nose is part of base body and stays stable across expressions.
    line(d, [(320, 253), (311, 284), (326, 288)], SKIN_SHADE, 7)
    return im


def draw_breast() -> Image.Image:
    """Draw only the standalone female breast layer (the MILK gem part)."""
    im = canvas()
    d = ImageDraw.Draw(im)
    # No shoulders, torso, waist, head or limbs belong in this sprite.
    d.ellipse((218, 405, 328, 552), fill=INK)
    d.ellipse((312, 405, 422, 552), fill=INK)
    d.ellipse((229, 416, 321, 541), fill=SUIT_MID)
    d.ellipse((319, 416, 411, 541), fill=SUIT_MID)
    line(d, [(235, 488), (286, 516), (320, 482), (354, 516), (405, 488)], SUIT_LIGHT, 12)
    line(d, [(259, 446), (282, 432)], WHITE, 7)
    line(d, [(381, 446), (358, 432)], WHITE, 7)
    return im


def draw_heart() -> Image.Image:
    im = canvas()
    d = ImageDraw.Draw(im)
    # Chest core is independently transformable as HEART.
    d.ellipse((284, 492, 324, 533), fill=INK)
    d.ellipse((316, 492, 356, 533), fill=INK)
    d.polygon([(283, 514), (357, 514), (320, 565)], fill=INK)
    d.ellipse((294, 501, 321, 527), fill=GEM)
    d.ellipse((319, 501, 346, 527), fill=GEM)
    d.polygon([(294, 516), (346, 516), (320, 549)], fill=GEM)
    line(d, [(309, 510), (320, 530), (334, 506)], WHITE, 5)
    return im


def draw_hair() -> Image.Image:
    im = canvas()
    d = ImageDraw.Draw(im)
    # Front crown, side locks, bangs and antenna curl.
    d.pieslice((198, 78, 442, 315), 180, 360, fill=INK)
    d.pieslice((210, 90, 430, 300), 180, 360, fill=HAIR_MID)
    d.polygon([(211, 188), (249, 126), (268, 233), (309, 122), (325, 239),
               (371, 130), (381, 232), (428, 177), (410, 285), (365, 238),
               (320, 274), (273, 238), (227, 287)], fill=INK)
    d.polygon([(222, 186), (246, 145), (259, 248), (305, 141), (317, 252),
               (367, 147), (369, 246), (416, 190), (399, 269), (361, 226),
               (320, 258), (277, 226), (239, 270)], fill=HAIR_MID)
    d.polygon([(215, 220), (248, 253), (235, 405), (186, 484), (204, 303)], fill=INK)
    d.polygon([(425, 220), (392, 253), (405, 405), (454, 484), (436, 303)], fill=INK)
    d.polygon([(224, 238), (238, 263), (225, 389), (202, 436), (216, 305)], fill=HAIR_DARK)
    d.polygon([(416, 238), (402, 263), (415, 389), (438, 436), (424, 305)], fill=HAIR_DARK)
    line(d, [(321, 100), (350, 54), (386, 80)], HAIR_LIGHT, 14)
    return im


def draw_eyes(expression: str) -> Image.Image:
    im = canvas()
    d = ImageDraw.Draw(im)
    if expression == "happy" or expression == "gorgeous":
        line(d, [(255, 261), (274, 274), (293, 260)], INK, 11)
        line(d, [(347, 260), (366, 274), (385, 261)], INK, 11)
    else:
        size = 36 if expression == "surprised" else 30
        d.ellipse((274 - size, 264 - size // 2, 274 + size, 264 + size // 2 + 13), fill=WHITE, outline=INK, width=9)
        d.ellipse((366 - size, 264 - size // 2, 366 + size, 264 + size // 2 + 13), fill=WHITE, outline=INK, width=9)
        d.ellipse((263, 255, 285, 286), fill=HAIR_DARK)
        d.ellipse((355, 255, 377, 286), fill=HAIR_DARK)
        d.ellipse((269, 260, 277, 270), fill=WHITE)
        d.ellipse((361, 260, 369, 270), fill=WHITE)
    if expression == "serious":
        line(d, [(239, 229), (294, 241)], INK, 10)
        line(d, [(346, 241), (401, 229)], INK, 10)
    elif expression == "sad":
        line(d, [(240, 244), (293, 228)], INK, 10)
        line(d, [(347, 228), (400, 244)], INK, 10)
    else:
        line(d, [(240, 232), (292, 227)], INK, 9)
        line(d, [(348, 227), (400, 232)], INK, 9)
    if expression == "gorgeous":
        for x in (231, 409):
            line(d, [(x, 278), (x - 9 if x < 320 else x + 9, 287)], GEM, 7)
    return im


def draw_voice(expression: str) -> Image.Image:
    im = canvas()
    d = ImageDraw.Draw(im)
    if expression == "surprised":
        d.ellipse((300, 310, 340, 358), fill=INK)
        d.ellipse((310, 321, 330, 349), fill=GEM)
    elif expression == "sad":
        d.arc((289, 326, 351, 369), 205, 335, fill=INK, width=10)
    elif expression in ("happy", "gorgeous"):
        d.arc((282, 294, 358, 358), 18, 162, fill=INK, width=11)
        if expression == "gorgeous":
            d.ellipse((305, 335, 335, 344), fill=GEM)
    else:
        line(d, [(296, 333), (344, 333)], INK, 9)
    return im


def draw_hands() -> Image.Image:
    im = canvas()
    d = ImageDraw.Draw(im)
    # Arms, gloves and hands are one layer because the gem word is plural.
    d.polygon([(224, 421), (191, 425), (132, 542), (82, 626), (132, 665),
               (194, 584), (263, 484)], fill=INK)
    d.polygon([(416, 421), (449, 425), (508, 542), (558, 626), (508, 665),
               (446, 584), (377, 484)], fill=INK)
    d.polygon([(221, 438), (201, 442), (148, 550), (106, 621), (133, 642),
               (177, 572), (249, 475)], fill=SUIT_MID)
    d.polygon([(419, 438), (439, 442), (492, 550), (534, 621), (507, 642),
               (463, 572), (391, 475)], fill=SUIT_MID)
    d.ellipse((69, 603, 145, 685), fill=INK)
    d.ellipse((495, 603, 571, 685), fill=INK)
    d.ellipse((82, 613, 135, 673), fill=SKIN)
    d.ellipse((505, 613, 558, 673), fill=SKIN)
    # Fingers and luminous gauntlet bands.
    for offset in (0, 13, 26):
        line(d, [(93 + offset, 628), (87 + offset, 664)], SKIN_SHADE, 5)
        line(d, [(547 - offset, 628), (553 - offset, 664)], SKIN_SHADE, 5)
    line(d, [(142, 555), (181, 577)], SUIT_LIGHT, 13)
    line(d, [(498, 555), (459, 577)], SUIT_LIGHT, 13)
    return im


BASE_DRAWERS: dict[str, Callable[[], Image.Image]] = {
    "back": draw_back,
    "legs": draw_legs,
    "body": draw_body,
    "breast": draw_breast,
    "heart": draw_heart,
    "hair": draw_hair,
    "hands": draw_hands,
}


def save_webp(image: Image.Image, path: Path) -> None:
    if image.mode != "RGBA" or image.getchannel("A").getextrema()[0] != 0:
        raise ValueError(f"{path.name}: layer must retain transparent pixels")
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, "WEBP", lossless=True, quality=100, method=6, exact=True)
    data = path.read_bytes()[:128]
    if data[:4] != b"RIFF" or data[8:12] != b"WEBP" or b"VP8L" not in data:
        raise ValueError(f"{path.name}: Pillow did not produce lossless WebP")


def generate(destination: Path) -> list[Path]:
    written: list[Path] = []
    for part, drawer in BASE_DRAWERS.items():
        path = destination / f"{part}.webp"
        save_webp(drawer(), path)
        written.append(path)
    # EYES and VOICE are still independent body parts. Their five redraws let
    # expressions change without ever falling back to an old full-body plate.
    for expression in EXPRESSIONS:
        expression_dir = destination / "expressions" / expression
        for part, image in (("eyes", draw_eyes(expression)), ("voice", draw_voice(expression))):
            path = expression_dir / f"{part}.webp"
            save_webp(image, path)
            written.append(path)
    return written


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEST, help="override output directory")
    args = parser.parse_args()
    written = generate(args.output)
    print(f"Drew {len(written)} lossless WebP files ({len(PARTS)} semantic layers per expression).")
    for path in written:
        print(path.relative_to(ROOT) if path.is_relative_to(ROOT) else path)


if __name__ == "__main__":
    main()

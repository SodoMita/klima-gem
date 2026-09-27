#!/usr/bin/env python3
"""Draw Aurora's placeholder body parts as SEPARATE aligned images.

The Klima Gem show pairs a BODY PART gem (HANDS/EYES/LEGS/VOICE/HAIR/BACK/
HEART/SKIN/MILK) with a MODIFICATION gem, and the standing sprite must
respond on the part the gem named. The old approach (mask slices of the
hand-painted sprite, or one opaque full-body plate per pair) was rejected by
the human: every part is drawn here from scratch, programmatically, on ONE
shared 768x1376 canvas so all nine layers stack pixel-perfectly.

These are PLACEHOLDERS: a human artist repaints any assets/characters/parts/
*.webp file at the same canvas size and the runtime rig picks it up, nothing
else changes. Output is packed lossless WebP (VP8L), never PNG, per art
directive. parts.json carries per-part z-order + pivot (fraction of the
canvas, y down) so transforms scale around a sensible joint.

    python3 tools/draw_body_parts.py            # writes parts + parts.json
    python3 tools/draw_body_parts.py --preview  # also docs/parts_preview.webp
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "assets" / "characters" / "parts"

W, H = 768, 1376          # shared canvas, matches the base portrait aspect
SS = 3                    # supersample for clean anti-aliased edges

SKIN = (246, 222, 203)
SKIN_SHADE = (222, 188, 166)
DRESS = (38, 64, 96)
DRESS_TRIM = (120, 200, 235)
HAIR = (216, 198, 236)
HAIR_SHADE = (172, 148, 205)
IRIS = (90, 200, 220)
LIPS = (198, 118, 128)

EXPRESSIONS = ("happy", "sad", "serious", "surprised", "gorgeous")
# z: back-to-front paint order inside the runtime rig.
PART_META = {
    "BACK":  {"z": 0, "pivot": (0.500, 0.360)},
    "LEGS":  {"z": 1, "pivot": (0.500, 0.470)},
    "SKIN":  {"z": 2, "pivot": (0.500, 0.965)},
    "HAIR":  {"z": 3, "pivot": (0.500, 0.120)},
    "MILK":  {"z": 4, "pivot": (0.500, 0.300)},
    "HANDS": {"z": 5, "pivot": (0.500, 0.255)},
    "EYES":  {"z": 6, "pivot": (0.500, 0.128)},
    "VOICE": {"z": 7, "pivot": (0.487, 0.183)},
    "HEART": {"z": 8, "pivot": (0.470, 0.300)},
}


def n(v: float) -> int:
    return round(v * SS)


def canvas() -> Image.Image:
    return Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))


def capsule(d: ImageDraw.ImageDraw, x0: float, y0: float, x1: float, y1: float,
            r: float, fill: tuple[int, ...]) -> None:
    """Thick rounded stroke between two normalized points."""
    p0 = (n(x0 * W), n(y0 * H))
    p1 = (n(x1 * W), n(y1 * H))
    d.line([p0, p1], fill=fill, width=2 * n(r * W))
    d.ellipse([p0[0] - n(r * W), p0[1] - n(r * W), p0[0] + n(r * W), p0[1] + n(r * W)], fill=fill)
    d.ellipse([p1[0] - n(r * W), p1[1] - n(r * W), p1[0] + n(r * W), p1[1] + n(r * W)], fill=fill)


def ell(d: ImageDraw.ImageDraw, cx: float, cy: float, rx: float, ry: float,
        fill: tuple[int, ...]) -> None:
    d.ellipse([n((cx - rx) * W), n((cy - ry) * H), n((cx + rx) * W), n((cy + ry) * H)], fill=fill)


def soft(base: Image.Image, rgb: tuple[int, int, int], shade_rgb: tuple[int, int, int],
         strength: float = 0.36) -> Image.Image:
    """Shade a flat RGBA shape: darker toward the lower-right rim, faint
    top-left rim light. Placeholder lighting, deterministic, no references."""
    a = np.asarray(base.getchannel("A")).astype(np.float32) / 255.0
    yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]].astype(np.float32)
    gx = (xx / a.shape[1] - 0.5) + (yy / a.shape[0] - 0.5)
    lit = np.clip(0.5 - gx, 0.0, 1.0)
    edge = np.asarray(base.getchannel("A").filter(ImageFilter.GaussianBlur(n(9)))).astype(np.float32) / 255.0
    inner = np.clip(a - edge * 0.55, 0.0, 1.0)
    shade = np.clip(inner * strength * (0.35 + 0.65 * (1.0 - lit)), 0.0, 1.0)
    out = np.zeros((a.shape[0], a.shape[1], 4), dtype=np.float32)
    for c in range(3):
        col = rgb[c] * (1.0 - shade) + shade_rgb[c] * shade
        col = col + np.clip(lit - 0.62, 0.0, 1.0) * 26.0 * inner
        out[:, :, c] = np.clip(col, 0, 255)
    out[:, :, 3] = a * 255.0
    return Image.fromarray(out.astype(np.uint8), "RGBA")


def finish(img: Image.Image, name: str) -> Path:
    img = img.resize((W, H), Image.LANCZOS)
    path = DEST / f"{name}.webp"
    img.save(path, "WEBP", lossless=True, quality=100, exact=True)
    return path


# ---------------------------------------------------------------- parts


def draw_back() -> Image.Image:
    """Shoulder blades and upper-back silhouette peeking around the torso."""
    img = canvas()
    d = ImageDraw.Draw(img)
    mask = canvas()
    m = ImageDraw.Draw(mask)
    for sx in (-1.0, 1.0):
        cx = 0.5 + sx * 0.202
        ell(m, cx, 0.355, 0.052, 0.098, (255, 255, 255, 255))          # blade
        capsule(m, 0.5 + sx * 0.155, 0.285, 0.5 + sx * 0.238, 0.375, 0.026, (255, 255, 255, 255))
    ell(m, 0.500, 0.272, 0.100, 0.050, (255, 255, 255, 255))            # upper back band
    col = Image.new("RGBA", mask.size, SKIN + (255,))
    img = Image.composite(col, img, mask.getchannel("A"))
    img = soft(img, SKIN, SKIN_SHADE, 0.42)
    d = ImageDraw.Draw(img)
    ell(d, 0.500, 0.258, 0.052, 0.030, (0, 0, 0, 0))
    d.line([(n(0.5 * W), n(0.270 * H)), (n(0.5 * W), n(0.400 * H))],
           fill=SKIN_SHADE + (160,), width=n(3))
    return img


def draw_legs() -> Image.Image:
    mask = canvas()
    m = ImageDraw.Draw(mask)
    for sx in (-1.0, 1.0):
        hip = (0.5 + sx * 0.068, 0.490)
        knee = (0.5 + sx * 0.058, 0.700)
        ankle = (0.5 + sx * 0.046, 0.930)
        capsule(m, hip[0], hip[1], knee[0], knee[1], 0.056, (255, 255, 255, 255))
        capsule(m, knee[0], knee[1], ankle[0], ankle[1], 0.042, (255, 255, 255, 255))
        ell(m, 0.5 + sx * 0.048, 0.955, 0.044, 0.028, (255, 255, 255, 255))   # foot
    img = Image.composite(Image.new("RGBA", mask.size, SKIN + (255,)), canvas(), mask.getchannel("A"))
    img = soft(img, SKIN, SKIN_SHADE)
    sh = ImageDraw.Draw(img)                                                   # inner-leg shadow
    sh.line([(n(0.5 * W), n(0.505 * H)), (n(0.5 * W), n(0.660 * H))],
            fill=SKIN_SHADE + (170,), width=n(5))
    d = ImageDraw.Draw(img)
    for sx in (-1.0, 1.0):                                                    # boots
        ell(d, 0.5 + sx * 0.048, 0.898, 0.040, 0.056, DRESS + (255,))
        ell(d, 0.5 + sx * 0.050, 0.955, 0.042, 0.028, DRESS + (255,))
        d.rectangle([n((0.5 + sx * 0.048 - 0.040) * W), n(0.876 * H),
                     n((0.5 + sx * 0.048 + 0.040) * W), n(0.890 * H)], fill=DRESS_TRIM + (255,))
    return img


def _torso_shape(m: ImageDraw.ImageDraw) -> None:
    ell(m, 0.500, 0.115, 0.088, 0.082, (255, 255, 255, 255))                  # head
    capsule(m, 0.495, 0.170, 0.495, 0.235, 0.026, (255, 255, 255, 255))       # neck
    capsule(m, 0.5 - 0.128, 0.252, 0.5 + 0.128, 0.252, 0.040, (255, 255, 255, 255))  # shoulders
    m.polygon([(n(0.372 * W), n(0.245 * H)), (n(0.628 * W), n(0.245 * H)),
               (n(0.588 * W), n(0.430 * H)), (n(0.412 * W), n(0.430 * H))],
              fill=(255, 255, 255, 255))                                      # torso
    ell(m, 0.500, 0.448, 0.096, 0.052, (255, 255, 255, 255))                  # pelvis


def draw_skin() -> Image.Image:
    mask = canvas()
    m = ImageDraw.Draw(mask)
    _torso_shape(m)
    img = Image.composite(Image.new("RGBA", mask.size, SKIN + (255,)), canvas(), mask.getchannel("A"))
    img = soft(img, SKIN, SKIN_SHADE)
    d = ImageDraw.Draw(img)
    # Leotard: the placeholder reads as dressed without a wardrobe system.
    d.polygon([(n(0.392 * W), n(0.258 * H)), (n(0.608 * W), n(0.258 * H)),
               (n(0.586 * W), n(0.438 * H)), (n(0.414 * W), n(0.438 * H))],
              fill=DRESS + (255,))
    ell(d, 0.500, 0.446, 0.094, 0.050, DRESS + (255,))
    d.line([(n(0.392 * W), n(0.262 * H)), (n(0.608 * W), n(0.262 * H))],
           fill=DRESS_TRIM + (255,), width=n(4))
    for sx in (-1.0, 1.0):                                                    # straps
        capsule(d, 0.5 + sx * 0.075, 0.252, 0.5 + sx * 0.062, 0.215, 0.010, DRESS + (255,))
    ell(d, 0.500, 0.105, 0.020, 0.012, (236, 205, 182, 255))                  # nose hint
    ell(d, 0.500, 0.076, 0.030, 0.014, (140, 90, 90, 90))                     # brow shade
    return img


def draw_hands() -> Image.Image:
    mask = canvas()
    m = ImageDraw.Draw(mask)
    for sx in (-1.0, 1.0):
        sh = (0.5 + sx * 0.140, 0.252)
        elb = (0.5 + sx * 0.190, 0.352)
        wr = (0.5 + sx * 0.196, 0.448)
        capsule(m, sh[0], sh[1], elb[0], elb[1], 0.034, (255, 255, 255, 255))
        capsule(m, elb[0], elb[1], wr[0], wr[1], 0.028, (255, 255, 255, 255))
        ell(m, wr[0], wr[1] + 0.022, 0.034, 0.042, (255, 255, 255, 255))      # palm
        for f in range(4):                                                    # finger stubs
            fx = wr[0] + sx * (-0.018 + f * 0.012)
            capsule(m, fx, wr[1] + 0.045, fx, wr[1] + 0.072, 0.0065, (255, 255, 255, 255))
    img = Image.composite(Image.new("RGBA", mask.size, SKIN + (255,)), canvas(), mask.getchannel("A"))
    img = soft(img, SKIN, SKIN_SHADE)
    d = ImageDraw.Draw(img)
    for sx in (-1.0, 1.0):
        capsule(d, 0.5 + sx * 0.196, 0.444, 0.5 + sx * 0.196, 0.452, 0.020, DRESS_TRIM + (255,))  # wristband
    return img


def draw_hair() -> Image.Image:
    """Front-readable hair: crown, bangs, and long side locks that frame the
    body without painting over the torso (the layer above SKIN still lets the
    dress read)."""
    mask = canvas()
    m = ImageDraw.Draw(mask)
    ell(m, 0.500, 0.096, 0.110, 0.086, (255, 255, 255, 255))                  # crown
    for sx in (-1.0, 1.0):                                                    # side locks
        capsule(m, 0.5 + sx * 0.100, 0.100, 0.5 + sx * 0.170, 0.250, 0.028, (255, 255, 255, 255))
        capsule(m, 0.5 + sx * 0.170, 0.250, 0.5 + sx * 0.184, 0.390, 0.022, (255, 255, 255, 255))
        ell(m, 0.5 + sx * 0.186, 0.402, 0.024, 0.022, (255, 255, 255, 255))   # lock tips
    face = canvas()                                                            # face opening
    f = ImageDraw.Draw(face)
    ell(f, 0.486, 0.124, 0.066, 0.078, (255, 255, 255, 255))
    mask = ImageChops.subtract(mask, face)
    img = Image.composite(Image.new("RGBA", mask.size, HAIR + (255,)), canvas(), mask.getchannel("A"))
    img = soft(img, HAIR, HAIR_SHADE, 0.42)
    d = ImageDraw.Draw(img)
    d.pieslice([n(0.398 * W), n(0.018 * H), n(0.602 * W), n(0.146 * H)],
               start=180, end=360, fill=HAIR + (255,))                        # crown cap
    for bx in (0.430, 0.500, 0.570):                                          # bangs
        d.polygon([(n((bx - 0.042) * W), n(0.080 * H)), (n((bx + 0.042) * W), n(0.080 * H)),
                   (n(bx * W), n(0.122 * H))], fill=HAIR + (255,))
    for sx in (-1.0, 1.0):                                                    # face-framing strands
        capsule(d, 0.5 + sx * 0.098, 0.075, 0.5 + sx * 0.096, 0.185, 0.013, HAIR + (255,))
    d.arc([n(0.404 * W), n(0.028 * H), n(0.596 * W), n(0.128 * H)],
          start=200, end=340, fill=(245, 240, 252, 220), width=n(5))
    return img


def _eye(d: ImageDraw.ImageDraw, cx: float, cy: float, s: float, mode: str) -> None:
    rx, ry = 0.040 * s, 0.019 * s
    if mode == "closed":
        d.arc([n((cx - rx) * W), n((cy - ry) * H), n((cx + rx) * W), n((cy + ry) * H)],
              start=200, end=340, fill=(70, 44, 52, 255), width=n(7))
    elif mode == "open":
        ell(d, cx, cy, rx, ry, (252, 250, 252, 255))
        ell(d, cx, cy + 0.0015, rx * 0.58, ry * 0.80, IRIS + (255,))
        ell(d, cx, cy + 0.0015, rx * 0.26, ry * 0.42, (30, 32, 44, 255))
        ell(d, cx - rx * 0.20, cy - ry * 0.28, rx * 0.14, ry * 0.20, (255, 255, 255, 250))
    lid_w = n(6)
    if mode == "serious":
        d.line([(n((cx - rx) * W), n((cy - ry * 1.35) * H)), (n((cx + rx) * W), n((cy - ry * 0.55) * H))],
               fill=(70, 44, 52, 255), width=lid_w)
    elif mode == "sad":
        d.line([(n((cx - rx) * W), n((cy - ry * 0.85) * H)), (n((cx + rx) * W), n((cy - ry * 1.55) * H))],
               fill=(70, 44, 52, 190), width=lid_w)
    else:
        d.arc([n((cx - rx * 1.05) * W), n((cy - ry * 1.3) * H), n((cx + rx * 1.05) * W), n((cy + ry * 0.9) * H)],
              start=185, end=355, fill=(70, 44, 52, 255), width=lid_w)


def draw_eyes(expression: str = "") -> Image.Image:
    img = canvas()
    d = ImageDraw.Draw(img)
    cy = 0.128
    style = {"happy": ("closed", 0.96), "gorgeous": ("closed", 1.0)}.get(expression, ("open", 1.0))
    if expression == "surprised":
        style = ("open", 1.3)
    if expression == "serious":
        style = ("open", 0.9)
    if expression == "sad":
        style = ("open", 1.02)
    for i, sx in enumerate((-1.0, 1.0)):
        cx = 0.486 + sx * 0.058
        mode, s = style
        if expression == "gorgeous" and i == 1:
            mode, s = "closed", 0.9                              # soft wink
        _eye(d, cx, cy, s, ("closed" if mode == "closed" else "open"))
        if expression == "serious" and mode == "open":
            _eye(d, cx, cy, s, "serious")
        if expression == "sad" and mode == "open":
            _eye(d, cx, cy, s, "sad")
        if expression == "surprised":
            d.arc([n((cx - 0.030) * W), n(0.088 * H), n((cx + 0.030) * W), n(0.104 * H)],
                  start=180, end=360, fill=(70, 44, 52, 220), width=n(5))
    if expression == "gorgeous":
        for sx in (-1.0, 1.0):                                   # blush
            ell(d, 0.486 + sx * 0.105, 0.152, 0.028, 0.013, (244, 150, 160, 110))
    return img


def draw_voice(expression: str = "") -> Image.Image:
    img = canvas()
    d = ImageDraw.Draw(img)
    cx, cy = 0.486, 0.180
    if expression in ("happy", "gorgeous"):
        d.arc([n((cx - 0.036) * W), n((cy - 0.016) * H), n((cx + 0.036) * W), n((cy + 0.018) * H)],
              start=20, end=160, fill=LIPS + (255,), width=n(8))
        if expression == "gorgeous":
            d.arc([n((cx - 0.030) * W), n((cy - 0.014) * H), n((cx + 0.030) * W), n((cy + 0.026) * H)],
                  start=15, end=165, fill=(120, 60, 70, 160), width=n(4))
    elif expression == "surprised":
        ell(d, cx, cy + 0.004, 0.014, 0.013, (150, 70, 80, 255))
        ell(d, cx, cy + 0.002, 0.008, 0.007, (90, 40, 50, 255))
    elif expression == "sad":
        d.arc([n((cx - 0.030) * W), n(cy * H), n((cx + 0.030) * W), n((cy + 0.030) * H)],
              start=200, end=340, fill=LIPS + (255,), width=n(7))
    elif expression == "serious":
        d.line([(n((cx - 0.030) * W), n((cy + 0.002) * H)), (n((cx + 0.030) * W), n((cy + 0.002) * H))],
               fill=LIPS + (255,), width=n(7))
    else:
        d.arc([n((cx - 0.028) * W), n((cy - 0.012) * H), n((cx + 0.028) * W), n((cy + 0.016) * H)],
              start=25, end=155, fill=LIPS + (255,), width=n(7))
    ell(d, 0.500, 0.212, 0.012, 0.008, (255, 190, 200, 90))      # throat marker
    return img


def draw_heart() -> Image.Image:
    img = canvas()
    cx, cy, s = 0.470, 0.300, 1.0
    glow = canvas()
    g = ImageDraw.Draw(glow)
    ell(g, cx, cy, 0.055 * s, 0.042 * s, (255, 120, 160, 72))
    glow = glow.filter(ImageFilter.GaussianBlur(n(8)))
    img = Image.alpha_composite(img, glow)
    d = ImageDraw.Draw(img)
    r = 0.030 * s
    ell(d, cx - r * 0.55, cy - r * 0.35, r * 0.62, r * 0.55, (255, 110, 150, 235))
    ell(d, cx + r * 0.55, cy - r * 0.35, r * 0.62, r * 0.55, (255, 110, 150, 235))
    d.polygon([(n((cx - r * 1.12) * W), n((cy - r * 0.10) * H)),
               (n((cx + r * 1.12) * W), n((cy - r * 0.10) * H)),
               (n(cx * W), n((cy + r * 1.15) * H))], fill=(255, 110, 150, 235))
    ell(d, cx - r * 0.42, cy - r * 0.52, r * 0.16, r * 0.12, (255, 235, 240, 220))
    return img


def draw_milk() -> Image.Image:
    """Bust forms, dress-toned so the layered composite still reads clothed."""
    top = tuple(min(255, c + 26) for c in DRESS)
    shade = tuple(max(0, c - 16) for c in DRESS)
    mask = canvas()
    m = ImageDraw.Draw(mask)
    for sx in (-1.0, 1.0):
        ell(m, 0.5 + sx * 0.048, 0.298, 0.048, 0.046, (255, 255, 255, 255))
    img = Image.composite(Image.new("RGBA", mask.size, top + (255,)), canvas(), mask.getchannel("A"))
    img = soft(img, top, shade, 0.42)
    d = ImageDraw.Draw(img)
    d.line([(n(0.5 * W), n(0.272 * H)), (n(0.5 * W), n(0.318 * H))], fill=shade + (220,), width=n(4))
    for sx in (-1.0, 1.0):
        d.arc([n((0.5 + sx * 0.048 - 0.042) * W), n(0.260 * H),
               n((0.5 + sx * 0.048 + 0.042) * W), n(0.318 * H)],
              start=180, end=330 if sx < 0 else 360, fill=DRESS_TRIM + (140,), width=n(4))
    return img


DRAWERS = {
    "BACK": draw_back,
    "LEGS": draw_legs,
    "SKIN": draw_skin,
    "HAIR": draw_hair,
    "MILK": draw_milk,
    "HANDS": draw_hands,
    "EYES": draw_eyes,
    "VOICE": draw_voice,
    "HEART": draw_heart,
}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", action="store_true", help="also write docs/parts_preview.webp")
    args = ap.parse_args()
    DEST.mkdir(parents=True, exist_ok=True)

    layers: dict[str, Image.Image] = {}
    meta = {"canvas": [W, H], "aspect": W / H, "parts": {}}
    for part, draw in DRAWERS.items():
        img = draw()
        layers[part] = img.resize((W, H), Image.LANCZOS)
        path = finish(img, part.lower())
        print("drew", path.relative_to(ROOT))
        entry = dict(PART_META[part])
        entry["file"] = f"{part.lower()}.webp"
        meta["parts"][part] = entry

    for expr in EXPRESSIONS:
        for part in ("EYES", "VOICE"):
            variant = DRAWERS[part](expr)
            name = f"{part.lower()}_{expr}"
            layers[name] = variant.resize((W, H), Image.LANCZOS)
            print("drew", finish(variant, name).relative_to(ROOT))
        meta["parts"]["EYES"].setdefault("variants", {})[expr] = f"eyes_{expr}.webp"
        meta["parts"]["VOICE"].setdefault("variants", {})[expr] = f"voice_{expr}.webp"

    (DEST / "parts.json").write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    print("wrote", (DEST / "parts.json").relative_to(ROOT))

    if args.preview:
        stack = Image.new("RGBA", (W, H), (58, 60, 78, 255))
        for part in sorted(meta["parts"], key=lambda p: meta["parts"][p]["z"]):
            stack = Image.alpha_composite(stack, layers[part])
        docs = ROOT / "docs"
        docs.mkdir(exist_ok=True)
        preview = docs / "parts_preview.webp"
        stack.save(preview, "WEBP", lossless=True, quality=100, exact=True)
        print("wrote", preview.relative_to(ROOT))


if __name__ == "__main__":
    main()

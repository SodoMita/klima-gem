#!/usr/bin/env python3
"""Slice cast portraits into body-part layers + ownership masks (placeholders).

The human redraws any part later; the composite reproduces an unmodded sprite
EXACTLY (each pixel owned by exactly one part, claimed highest z first), so the
runtime composer and the 2D body doll can rebuild her byte for byte.

    python3 tools/split_body_parts.py [--character aurora] [--debug-sheet]

Reads  characters/body/body_manifest.json
       assets/characters/<char>_<expr>.webp
Writes assets/characters/body/<key>__<part>.webp    (cropped RGBA, lossless)
       assets/characters/body/<key>__<part>_mask.webp (full-size L, lossless)
       assets/characters/body/<key>__body.json       (bboxes, px anchors)
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "characters" / "body" / "body_manifest.json"


def load_manifest() -> dict:
    return json.loads(MANIFEST.read_text())


def claim_mask(claim: dict, w: int, h: int) -> np.ndarray:
    y, x = np.mgrid[0:h, 0:w].astype(np.float64)
    nx, ny = x / w, y / h
    t = claim["type"]
    if t == "rect":
        m = (nx >= claim["x"][0]) & (nx <= claim["x"][1]) & (ny >= claim["y"][0]) & (ny <= claim["y"][1])
        me = claim.get("minus_ellipse")
        if me:
            e = (((nx - me["c"][0]) / me["r"][0]) ** 2 + ((ny - me["c"][1]) / me["r"][1]) ** 2) <= 1.0
            m &= ~e
        return m
    if t == "sides":
        lx = (nx >= claim["outer_x"][0]) & (nx <= claim["outer_x"][1])
        rx = (nx >= claim["inner_x"][0]) & (nx <= claim["inner_x"][1])
        yy = (ny >= claim["y"][0]) & (ny <= claim["y"][1])
        return (lx | rx) & yy
    return np.zeros((h, w), dtype=bool)


def dilate(mask: np.ndarray, px: int) -> np.ndarray:
    from PIL import ImageFilter

    im = Image.fromarray((mask * 255).astype(np.uint8))
    im = im.filter(ImageFilter.MaxFilter(px * 2 + 1))
    return np.asarray(im) > 0


def split(key: str, src: Image.Image, manifest: dict) -> tuple[dict, dict[str, np.ndarray]]:
    w, h = src.size
    arr = np.asarray(src.convert("RGBA"))
    alpha = arr[:, :, 3] > 8
    pool = alpha.copy()
    masks: dict[str, np.ndarray] = {}
    # Highest z claims first; "rest" mops up whatever is left of the body.
    ordered = sorted(manifest["parts"], key=lambda p: -p["z"])
    for part in ordered:
        claims = part["claims"]
        if claims[0]["type"] == "rim":
            ring = dilate(alpha, int(claims[0].get("outside_px", 10))) & ~alpha
            masks[part["id"]] = ring
        elif claims[0]["type"] == "rest":
            masks[part["id"]] = pool.copy()
            pool[:] = False
        else:
            want = np.zeros((h, w), dtype=bool)
            for c in claims:
                want |= claim_mask(c, w, h)
            own = want & pool
            masks[part["id"]] = own
            pool &= ~own
    meta = {"size": [w, h], "parts": {}, "overlays": {}}
    for part in manifest["parts"]:
        pid = part["id"]
        m = masks[pid]
        ys, xs = np.where(m)
        bbox = [int(xs.min()), int(ys.min()), int(xs.max() - xs.min() + 1), int(ys.max() - ys.min() + 1)] if len(xs) else [0, 0, 0, 0]
        meta["parts"][pid] = {
            "anchor_px": [round(part["anchor"][0] * w, 2), round(part["anchor"][1] * h, 2)],
            "bbox": bbox,
        }
    for ov in manifest["overlays"]:
        r = ov["rect"]
        meta["overlays"][ov["id"]] = {
            "rect_px": [round(r[0] * w, 2), round(r[1] * h, 2), round((r[2] - r[0]) * w, 2), round((r[3] - r[1]) * h, 2)],
            "anchor_px": [round(ov["anchor"][0] * w, 2), round(ov["anchor"][1] * h, 2)],
        }
    # the runtime treats "skin" as every owned non-hair pixel
    skin = np.zeros((h, w), dtype=bool)
    for pid, m in masks.items():
        if pid not in ("hair", "back"):
            skin |= m
    masks["skin"] = skin
    meta["parts"]["skin"] = {"anchor_px": [round(w / 2, 2), round(h / 2, 2)], "bbox": [0, 0, w, h]}
    return meta, masks


def save_lossless(im: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path, "WEBP", lossless=True, quality=100, method=4, exact=True)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--character", default="aurora")
    ap.add_argument("--debug-sheet", action="store_true")
    args = ap.parse_args()
    man = load_manifest()
    dest = ROOT / man["body_root"]
    char = man["characters"][args.character]
    for expr in char["expressions"]:
        key = f"{args.character}_{expr}"
        src_path = ROOT / man["source_root"] / f"{key}.webp"
        if not src_path.exists():
            print(f"skip {key}: no source {src_path}")
            continue
        src = Image.open(src_path).convert("RGBA")
        meta, masks = split(key, src, man)
        arr = np.asarray(src)
        for pid, m in masks.items():
            mask_img = Image.fromarray(np.where(m, 255, 0).astype(np.uint8), "L")
            save_lossless(mask_img, dest / f"{key}__{pid}_mask.webp")
            if pid == "skin":
                continue  # derived at runtime, no texture needed
            owned = arr.copy()
            owned[:, :, 3] = np.where(m, arr[:, :, 3], 0)
            x, y, w, h = meta["parts"][pid]["bbox"]
            if w and h:
                save_lossless(Image.fromarray(owned[y : y + h, x : x + w]), dest / f"{key}__{pid}.webp")
        (dest / f"{key}__body.json").write_text(json.dumps({"key": key, **meta}, indent=1))
        # reconstruct check: every alpha pixel owned exactly once, parts rebuild the source
        owned_count = sum(masks[p["id"]] for p in man["parts"])
        alpha = arr[:, :, 3] > 8
        assert not (owned_count[alpha] > 1).any(), f"{key}: double-owned pixels"
        rec = np.zeros_like(arr)
        for p in man["parts"]:
            m = masks[p["id"]]
            rec[m] = arr[m]
        same = bool((rec[alpha] == arr[alpha]).all() and (rec[:, :, 3][~alpha & ~masks["back"]] == 0).all())
        print(f"{key}: {src.size[0]}x{src.size[1]} parts={len(masks)} reconstruct={'exact' if same else 'FAIL'}")
        if args.debug_sheet:
            w, h = src.size
            ids = ["hair", "head", "arms", "torso", "legs", "body", "back"]
            colors = {"hair": (255, 80, 80), "head": (80, 255, 120), "arms": (90, 160, 255), "torso": (255, 230, 90), "legs": (255, 90, 220), "body": (90, 255, 240), "back": (200, 200, 255)}
            combo = np.zeros((h, w, 4), np.uint8)
            for pid in ids:
                m = masks[pid]
                combo[m, 0:3] = colors[pid]
                combo[m, 3] = 200
            sheet = Image.new("RGBA", (w * 2, h), (24, 24, 32, 255))
            sheet.paste(src, (0, 0))
            sheet.paste(src, (w, 0))
            sheet.paste(Image.fromarray(combo), (w, 0), Image.fromarray(combo))
            sheet.save(Path("/tmp") / f"bodyids_{key}.png")
    print("done ->", dest)


if __name__ == "__main__":
    main()

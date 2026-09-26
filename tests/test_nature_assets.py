#!/usr/bin/env python3
"""Fast integrity/budget checks for the curated Quaternius nature assets."""
from __future__ import annotations

import json
import sys
from pathlib import Path, PurePosixPath

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets/models/nature"
MAX_TEXTURE_BYTES = 500 * 1024
MAX_MODEL_BYTES = 512 * 1024
MAX_NATURE_PAYLOAD_BYTES = 3 * 1024 * 1024
EXPECTED_MODELS = {
    "CommonTree_3",
    "Pine_5",
    "Bush_Common",
    "Bush_Common_Flowers",
    "Fern_1",
    "Flower_3_Group",
    "Grass_Common_Tall",
    "Mushroom_Common",
    "Rock_Medium_1",
    "RockPath_Round_Wide",
}


def check() -> list[str]:
    errors: list[str] = []
    actual_models = {path.stem for path in ASSETS.glob("*.gltf")}
    if actual_models != EXPECTED_MODELS:
        errors.append(f"model set differs: missing={sorted(EXPECTED_MODELS - actual_models)}, extra={sorted(actual_models - EXPECTED_MODELS)}")

    webps = list((ASSETS / "textures").glob("*.webp"))
    if not webps:
        errors.append("no WebP textures found")
    for texture in webps:
        size = texture.stat().st_size
        if size >= MAX_TEXTURE_BYTES:
            errors.append(f"texture exceeds 500 KiB: {texture.relative_to(ROOT)} ({size} bytes)")
        try:
            with Image.open(texture) as image:
                image.verify()
        except Exception as exc:
            errors.append(f"invalid WebP {texture.relative_to(ROOT)}: {exc}")

    for model_path in sorted(ASSETS.glob("*.gltf")):
        try:
            doc = json.loads(model_path.read_text(encoding="utf-8"))
        except Exception as exc:
            errors.append(f"invalid JSON {model_path.name}: {exc}")
            continue

        if "EXT_texture_webp" not in doc.get("extensionsUsed", []):
            errors.append(f"{model_path.name} does not declare EXT_texture_webp")
        if "EXT_texture_webp" not in doc.get("extensionsRequired", []):
            errors.append(f"{model_path.name} does not require EXT_texture_webp")

        for buffer in doc.get("buffers", []):
            uri = buffer.get("uri", "")
            buffer_path = ASSETS / PurePosixPath(uri)
            if not buffer_path.is_file():
                errors.append(f"missing geometry buffer for {model_path.name}: {uri}")
            elif buffer_path.stat().st_size + model_path.stat().st_size >= MAX_MODEL_BYTES:
                errors.append(f"model+geometry exceeds 512 KiB: {model_path.name}")

        for image in doc.get("images", []):
            uri = image.get("uri", "")
            if not uri.lower().endswith(".webp"):
                errors.append(f"non-WebP texture reference in {model_path.name}: {uri}")
            if not (ASSETS / PurePosixPath(uri)).is_file():
                errors.append(f"missing texture for {model_path.name}: {uri}")

        for texture in doc.get("textures", []):
            extension = texture.get("extensions", {}).get("EXT_texture_webp", {})
            if "source" not in extension:
                errors.append(f"missing EXT_texture_webp source in {model_path.name}")

    if not (ASSETS / "LICENSE_Quaternius_CC0.txt").is_file():
        errors.append("Quaternius CC0 license text is missing")
    payload = sum(path.stat().st_size for path in ASSETS.rglob("*") if path.is_file())
    if payload >= MAX_NATURE_PAYLOAD_BYTES:
        errors.append(f"curated nature payload exceeds 3 MiB: {payload} bytes")
    return errors


def main() -> int:
    errors = check()
    if errors:
        print("Nature asset checks FAILED:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    payload = sum(path.stat().st_size for path in ASSETS.rglob("*") if path.is_file())
    print(f"Nature assets OK: {len(EXPECTED_MODELS)} models, {len(list((ASSETS / 'textures').glob('*.webp')))} WebP textures, {payload / 1024:.1f} KiB total.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

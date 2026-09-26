#!/usr/bin/env python3
"""Curate and optimize the free Quaternius Stylized Nature MEGAKIT Standard pack.

Usage:
    python3 tools/prepare_nature_assets.py --source-zip /path/to/Stylized_Nature_MegaKitStandard.zip

Only the small set used by the optional Whispering Grove showcase is copied into
this repository. The original 100 MB archive is deliberately not retained.
Requires Pillow (already listed in tools/requirements.txt).
"""
from __future__ import annotations

import argparse
import io
import json
import shutil
import sys
import zipfile
from pathlib import Path, PurePosixPath

from PIL import Image, ImageOps

PACK_MODELS = (
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
)
WEBP_EXTENSION = "EXT_texture_webp"
MAX_TEXTURE_BYTES = 500 * 1024
MAX_MODEL_BYTES = 512 * 1024  # .gltf JSON + its matching .bin geometry
MAX_EDGE_STEPS = (1024, 768, 512, 384, 256)


def encode_webp(source: bytes, name: str) -> tuple[bytes, tuple[int, int], tuple[int, int]]:
    """Resize only oversized source atlases; preserve alpha/normal data losslessly."""
    with Image.open(io.BytesIO(source)) as opened:
        opened.load()
        image = ImageOps.exif_transpose(opened)
        source_size = image.size
        has_alpha = "A" in image.getbands() or "transparency" in image.info
        is_normal_map = "normal" in name.lower()
        if has_alpha:
            image = image.convert("RGBA")
        else:
            image = image.convert("RGB")

        # Lossless WebP is important for cutout foliage and normal-map data.
        # Color-only atlases use high-quality lossy WebP to keep the repo lean.
        lossless = has_alpha or is_normal_map
        for max_edge in MAX_EDGE_STEPS:
            candidate = image.copy()
            candidate.thumbnail((max_edge, max_edge), Image.Resampling.LANCZOS)
            output = io.BytesIO()
            candidate.save(
                output,
                format="WEBP",
                lossless=lossless,
                quality=100 if lossless else 84,
                method=6,
                exact=True,
                alpha_quality=100,
            )
            data = output.getvalue()
            if len(data) <= MAX_TEXTURE_BYTES:
                return data, source_size, candidate.size
        raise ValueError(f"Unable to encode {name!r} below {MAX_TEXTURE_BYTES} bytes")


def safe_member(archive: zipfile.ZipFile, name: str) -> bytes:
    try:
        return archive.read(name)
    except KeyError as exc:
        raise ValueError(f"Required file missing from source archive: {name}") from exc


def prepare(source_zip: Path, destination: Path) -> None:
    if not source_zip.is_file():
        raise FileNotFoundError(source_zip)
    destination.mkdir(parents=True, exist_ok=True)
    texture_dir = destination / "textures"
    texture_dir.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(source_zip) as archive:
        license_text = safe_member(archive, "License_Standard.txt")
        (destination / "LICENSE_Quaternius_CC0.txt").write_bytes(license_text)

        parsed: dict[str, dict] = {}
        required_buffers: dict[str, bytes] = {}
        source_textures: dict[str, bytes] = {}

        for model_name in PACK_MODELS:
            model_path = f"glTF/{model_name}.gltf"
            document = json.loads(safe_member(archive, model_path))
            parsed[model_name] = document

            for buffer in document.get("buffers", []):
                uri = buffer.get("uri")
                if not uri or uri.startswith("data:"):
                    raise ValueError(f"Expected an external buffer URI in {model_path}: {uri!r}")
                member = str(PurePosixPath("glTF") / PurePosixPath(uri))
                required_buffers[uri] = safe_member(archive, member)

            for image in document.get("images", []):
                uri = image.get("uri")
                if not uri or uri.startswith("data:"):
                    raise ValueError(f"Expected an external texture URI in {model_path}: {uri!r}")
                member = str(PurePosixPath("glTF") / PurePosixPath(uri))
                source_textures[uri] = safe_member(archive, member)

        texture_stats: dict[str, dict] = {}
        for source_name, source_bytes in sorted(source_textures.items()):
            webp_bytes, before, after = encode_webp(source_bytes, source_name)
            target_name = f"{Path(source_name).stem}.webp"
            target_path = texture_dir / target_name
            target_path.write_bytes(webp_bytes)
            texture_stats[source_name] = {
                "path": f"textures/{target_name}",
                "source_bytes": len(source_bytes),
                "bytes": len(webp_bytes),
                "source_dimensions": list(before),
                "dimensions": list(after),
            }

        for model_name, document in parsed.items():
            for image in document.get("images", []):
                old_uri = image["uri"]
                image["uri"] = texture_stats[old_uri]["path"]
                # External images infer image/webp from the .webp URI. Keeping a
                # mimeType is unnecessary; the texture extension carries the image source.
                image.pop("mimeType", None)

            for texture in document.get("textures", []):
                if "source" not in texture:
                    raise ValueError(f"Texture without a core source in {model_name}.gltf")
                image_index = texture.pop("source")
                extensions = texture.setdefault("extensions", {})
                extensions[WEBP_EXTENSION] = {"source": image_index}

            for extension_list in ("extensionsUsed", "extensionsRequired"):
                values = document.setdefault(extension_list, [])
                if WEBP_EXTENSION not in values:
                    values.append(WEBP_EXTENSION)

            gltf_path = destination / f"{model_name}.gltf"
            gltf_path.write_text(json.dumps(document, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

        for uri, data in required_buffers.items():
            (destination / PurePosixPath(uri).name).write_bytes(data)

        # Fail before writing a manifest if anything violates the requested size budget.
        for texture_path in texture_dir.glob("*.webp"):
            if texture_path.stat().st_size >= MAX_TEXTURE_BYTES:
                raise ValueError(f"Texture exceeds the 500 KiB cap: {texture_path}")
        model_stats: dict[str, dict] = {}
        for model_name in PACK_MODELS:
            gltf_path = destination / f"{model_name}.gltf"
            buffer_uri = parsed[model_name]["buffers"][0]["uri"]
            buffer_path = destination / PurePosixPath(buffer_uri).name
            total = gltf_path.stat().st_size + buffer_path.stat().st_size
            if total >= MAX_MODEL_BYTES:
                raise ValueError(f"Model exceeds the 512 KiB JSON+geometry budget: {model_name} ({total} bytes)")
            model_stats[model_name] = {
                "gltf_bytes": gltf_path.stat().st_size,
                "geometry_bytes": buffer_path.stat().st_size,
                "combined_bytes": total,
            }

        manifest = {
            "source": "Quaternius Stylized Nature MEGAKIT Standard-1.0 (free Standard edition)",
            "license": "CC0 1.0 Universal",
            "textures_max_bytes": MAX_TEXTURE_BYTES,
            "models_max_combined_bytes": MAX_MODEL_BYTES,
            "models": model_stats,
            "textures": texture_stats,
        }
        (destination / "optimized_manifest.json").write_text(
            json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )

    print(f"Prepared {len(PACK_MODELS)} models and {len(texture_stats)} shared WebP textures in {destination}")
    print(f"Nature asset payload: {sum(p.stat().st_size for p in destination.rglob('*') if p.is_file()) / 1024:.1f} KiB")
    for name, stats in model_stats.items():
        print(f"  {name:24} {stats['combined_bytes']:>7,} B model+geometry")
    for name, stats in texture_stats.items():
        print(f"  {name:32} {stats['bytes']:>7,} B {stats['dimensions'][0]}x{stats['dimensions'][1]}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-zip", type=Path, required=True, help="Downloaded Standard pack ZIP")
    parser.add_argument("--output", type=Path, default=Path("assets/models/nature"), help="Output asset directory")
    args = parser.parse_args()
    try:
        prepare(args.source_zip, args.output)
    except (OSError, ValueError, zipfile.BadZipFile, json.JSONDecodeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

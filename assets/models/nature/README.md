# Stylized Nature MEGAKIT — curated Godot slice

This directory contains a deliberately small, game-ready subset of the **free Standard 1.0** edition of Quaternius's Stylized Nature MEGAKIT. The Standard pack is CC0; the original license text is retained in [`LICENSE_Quaternius_CC0.txt`](LICENSE_Quaternius_CC0.txt). No paid Pro or Source files are included.

- Pack: [Quaternius — Stylized Nature MEGAKIT](https://quaternius.com/packs/stylizednaturemegakit.html)
- Godot listing: [Godot Asset Store](https://store.godotengine.org/asset/quaternius/stylized-nature-megakit/)
- License: CC0 1.0 Universal / public domain dedication
- Creator: Quaternius

## Included models

`CommonTree_3`, `Pine_5`, `Bush_Common`, `Bush_Common_Flowers`, `Fern_1`, `Flower_3_Group`, `Grass_Common_Tall`, `Mushroom_Common`, `Rock_Medium_1`, and `RockPath_Round_Wide`.

The `.gltf` files and matching `.bin` geometry files are kept as standard glTF 2.0. Each model-plus-geometry payload is under 512 KiB. Shared texture atlases are converted to WebP, with alpha and normal-map data kept lossless and color atlases encoded at high quality; oversized atlases are resized only as needed. Every checked-in WebP is below 500 KiB (the largest is about 451 KiB). Models reference WebP through `EXT_texture_webp`, supported by the project's Godot 4.7 importer.

The selected assets, shared textures, manifest, and license total about 2.7 MiB. The 100 MB source archive and unused kit assets are intentionally not committed.

## Preview

Open `res://scenes/nature_showcase.tscn` in Godot and run the current scene (F6) to see a small Whispering Grove layout. It is a standalone asset showcase; the visual-novel's existing painted backgrounds and dialogue flow are unchanged.

## Rebuild the optimized slice

With the free Standard ZIP downloaded locally, run from the repository root:

```sh
python3 tools/prepare_nature_assets.py --source-zip /path/to/Stylized_Nature_MegaKitStandard.zip
python3 tests/test_nature_assets.py
godot --headless --editor --path . --import --quit
godot --headless --path . --script tests/nature_asset_smoke.gd
```

The preparation script keeps only the listed models, converts the referenced images, patches glTF texture references to `EXT_texture_webp`, and writes `optimized_manifest.json` with dimensions and byte counts. Pillow is included in `tools/requirements.txt`. The Godot smoke script confirms each model imports and has a decoded WebP albedo material.

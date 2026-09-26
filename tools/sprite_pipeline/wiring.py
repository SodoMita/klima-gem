"""Check dialogue sprite tags against the balloon dictionary and files.

A missing expression is a pipeline gap, reported by sprite_status.py, not a
wiring failure. A tag that names a key the balloon does not have is a failure:
the game would show an empty slot.
"""

from __future__ import annotations

import hashlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DIALOGUE = ROOT / "dialogue"
BALLOON = ROOT / "scenes" / "vn_balloon.tscn"
ASSETS = ROOT / "assets" / "characters"
SPRITES = ROOT / "Sprites"

TAG_RE = re.compile(r"#sprite=([A-Za-z0-9_]+):")
DICT_RE = re.compile(
    r"sprites = Dictionary\[String, Texture2D\]\(\{(.*?)\n\}\)",
    re.S,
)
KEY_RE = re.compile(r'"([^"]+)"\s*:')
PATH_RE = re.compile(r'path="res://assets/characters/([^"]+)"')


def dialogue_keys() -> dict[str, list[str]]:
    found: dict[str, list[str]] = {}
    for path in sorted(DIALOGUE.glob("*.dialogue")):
        text = path.read_text(encoding="utf-8")
        for match in TAG_RE.finditer(text):
            key = match.group(1)
            if key == "none":
                continue
            found.setdefault(key, []).append(str(path.relative_to(ROOT)))
    return found


def balloon_keys() -> dict[str, str]:
    text = BALLOON.read_text(encoding="utf-8")
    block = DICT_RE.search(text)
    if not block:
        raise SystemExit(f"sprite dictionary not found in {BALLOON}")
    keys = KEY_RE.findall(block.group(1))
    files = {Path(name).stem: name for name in PATH_RE.findall(text)}
    return {key: files.get(key, "") for key in keys}


def asset_files() -> list[str]:
    return sorted(
        p.name for p in ASSETS.iterdir()
        if p.is_file() and p.suffix != ".import"
    )


def duplicate_assets() -> list[tuple[str, list[str]]]:
    hashes: dict[str, list[str]] = {}
    for name in asset_files():
        digest = hashlib.sha256((ASSETS / name).read_bytes()).hexdigest()[:12]
        hashes.setdefault(digest, []).append(name)
    return [(digest, names) for digest, names in hashes.items() if len(names) > 1]


def wiring_errors() -> list[str]:
    errors = []
    keys = balloon_keys()
    for key, files in dialogue_keys().items():
        if key not in keys:
            where = ", ".join(sorted(set(files)))
            errors.append(f"dialogue sprite {key!r} is not in the balloon dictionary ({where})")
    for key, filename in keys.items():
        if not filename:
            errors.append(f"balloon key {key!r} has no ext_resource under assets/characters")
            continue
        if not (ASSETS / filename).exists():
            errors.append(f"balloon key {key!r} points at missing file {filename}")
    return errors


def status_lines() -> list[str]:
    lines = ["Sprite wiring", ""]
    errors = wiring_errors()
    if errors:
        lines.append("FAILURES:")
        lines.extend(f"  - {err}" for err in errors)
    else:
        lines.append("Dialogue tags, balloon keys, and asset files agree.")
    lines.append("")
    lines.append("Duplicate asset bytes (same picture under two names):")
    dupes = duplicate_assets()
    if not dupes:
        lines.append("  none")
    for digest, names in dupes:
        lines.append(f"  {digest}  {', '.join(names)}")
    used = set(dialogue_keys())
    unused = sorted(set(balloon_keys()) - used)
    lines.append("")
    lines.append("Balloon keys never referenced by a #sprite tag:")
    lines.append("  " + (", ".join(unused) if unused else "none"))
    orphan_files = []
    keyed = set(balloon_keys())
    for name in asset_files():
        if Path(name).stem not in keyed:
            orphan_files.append(name)
    lines.append("")
    lines.append("Asset files with no balloon key:")
    lines.append("  " + (", ".join(orphan_files) if orphan_files else "none"))
    if SPRITES.exists():
        sprite_names = {p.name for p in SPRITES.iterdir() if p.suffix != ".import"}
        asset_names = set(asset_files())
        only_sprites = sorted(sprite_names - asset_names)
        only_assets = sorted(asset_names - sprite_names)
        lines.append("")
        lines.append("Sprites/ vs assets/characters/ name drift:")
        lines.append("  only in Sprites/: " + (", ".join(only_sprites) if only_sprites else "none"))
        lines.append("  only in assets/characters/: " + (", ".join(only_assets) if only_assets else "none"))
    return lines

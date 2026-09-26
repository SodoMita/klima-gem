"""Short cast file. Edit characters/cast.json. Do not render a second copy."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CAST = ROOT / "characters" / "cast.json"
LEVELS = ("L0", "L1", "L2", "L3", "L4")


def load(path: Path | None = None) -> dict:
    path = path or CAST
    doc = json.loads(path.read_text(encoding="utf-8"))
    if not doc.get("characters"):
        raise SystemExit(f"{path} has no characters")
    return doc


def find(doc: dict, cid: str) -> dict:
    for ch in doc["characters"]:
        if ch["id"] == cid:
            return ch
    known = ", ".join(ch["id"] for ch in doc["characters"])
    raise SystemExit(f"unknown character {cid!r}; known: {known}")


def prompt(doc: dict, ch: dict) -> str:
    lines = [
        f"base: {doc['base']}",
        f"clothes: {ch.get('clothes') or '?'}",
        f"{ch['name']}. {ch['L0']}",
    ]
    for key in LEVELS[1:]:
        if ch.get(key):
            lines.append(f"{key}: {ch[key]}")
    if ch.get("ask"):
        lines.append(f"ask: {ch['ask']}")
    return "\n".join(lines)


def check(doc: dict) -> list[str]:
    errors = []
    if doc.get("base") != "bikini":
        errors.append("base must stay bikini until edited on purpose")
    if "clothes" not in doc.get("layers", []):
        errors.append("layers must include clothes")
    seen = set()
    for ch in doc["characters"]:
        cid = ch.get("id", "?")
        if cid in seen:
            errors.append(f"duplicate id {cid}")
        seen.add(cid)
        for key in ("name", *LEVELS, "clothes", "ask"):
            if key not in ch:
                errors.append(f"{cid}: missing {key}")
    return errors

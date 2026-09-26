#!/usr/bin/env python3
"""Wiring report plus which cast fields are still empty."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from sprite_pipeline.cast import LEVELS, load  # noqa: E402
from sprite_pipeline.wiring import status_lines, wiring_errors  # noqa: E402


def main() -> int:
    print("\n".join(status_lines()))
    print("")
    for ch in load()["characters"]:
        empty = [key for key in (*LEVELS, "clothes") if not ch.get(key)]
        ask = ch.get("ask") or ""
        print(f"{ch['id']}: empty={','.join(empty) or '-'}  ask={ask}")
    return 1 if wiring_errors() else 0


if __name__ == "__main__":
    raise SystemExit(main())

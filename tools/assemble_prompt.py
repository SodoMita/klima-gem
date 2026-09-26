#!/usr/bin/env python3
"""Print a short prompt from characters/cast.json. Empty fields stay empty."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from sprite_pipeline.cast import find, load, prompt  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("character")
    args = ap.parse_args()
    doc = load()
    print(prompt(doc, find(doc, args.character)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Fail if a dialogue #sprite tag is not wired to a real texture."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from sprite_pipeline.wiring import status_lines, wiring_errors  # noqa: E402


def main() -> int:
    print("\n".join(status_lines()))
    errors = wiring_errors()
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())

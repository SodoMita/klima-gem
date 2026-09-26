#!/bin/sh
set -e
cd "$(dirname "$0")/.."
case "${1:-}" in
  check)
    python3 -c 'import sys; sys.path.insert(0,"tools"); from sprite_pipeline.cast import check, load; e=check(load()); print("\n".join(e)); raise SystemExit(1 if e else 0)'
    python3 tools/check_sprite_wiring.py
    ;;
  status) python3 tools/sprite_status.py ;;
  prompt) shift; python3 tools/assemble_prompt.py "$@" ;;
  *) echo "usage: tools/sprite_pipeline.sh check|status|prompt <id>" >&2; exit 1 ;;
esac

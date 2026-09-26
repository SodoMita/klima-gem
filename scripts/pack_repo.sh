#!/usr/bin/env bash
# pack_repo.sh — package the Chrono Nexus Godot project into a single
# .tar.gz archive, suitable for moving between machines.
#
# What it includes:
#   * All working-tree files (including addons/, Sprites/, bgs/,
#     characters/, timelines/, docs/, etc.).
#   * Optionally .git/ (the project's git history, or its separate-
#     git-dir location if you used `git init --separate-git-dir`).
#
# What it excludes:
#   * .godot/ (Godot's per-machine import cache; regenerated on
#     first run via `godot --headless --import`).
#   * *.log (test artifacts).
#   * Editor cruft (*.swp, *.swo, *~, .DS_Store).
#   * Anything matching the secrets patterns in .gitignore.
#
# Usage:
#   scripts/pack_repo.sh                         # writes to ~/chrono-nexus-<date>.tar.gz
#   scripts/pack_repo.sh -o path/to/x.tgz        # writes to that path
#   scripts/pack_repo.sh --no-git                # exclude git history
#   scripts/pack_repo.sh --git-from <dir>        # read .git from a separate-git-dir
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT=""
INCLUDE_GIT=1
GIT_FROM=""

while [ $# -gt 0 ]; do
  case "$1" in
    -o|--output) OUT="$2"; shift 2 ;;
    --no-git|--no-history) INCLUDE_GIT=0; shift ;;
    --git-from) GIT_FROM="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,30p' "$0"
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

# Default output: write under $HOME so the file is easy to find and
# download.
if [ -z "$OUT" ]; then
  OUT="$HOME/chrono-nexus-$(date -u +%Y%m%d-%H%M%S).tar.gz"
fi

# Build the tar exclusion list.
EXCLUDES=(
  --exclude=".godot"
  --exclude=".godot/**"
  --exclude="*.log"
  --exclude="*.swp"
  --exclude="*.swo"
  --exclude="*~"
  --exclude=".DS_Store"
  --exclude=".env"
  --exclude=".env.*"
  --exclude="secrets"
  --exclude="secrets/**"
  --exclude="credentials"
  --exclude="credentials/**"
  --exclude="tests/output"
  --exclude="tests/output/**"
)
if [ "$INCLUDE_GIT" -eq 0 ]; then
  EXCLUDES+=(--exclude=".git" --exclude=".git/**")
fi

# Resolve the actual .git directory. If it's a "gitdir: <path>" file
# (from `git init --separate-git-dir`), use that path so the archive
# contains a real history.
GIT_SRC=""
if [ "$INCLUDE_GIT" -eq 1 ]; then
  if [ -n "$GIT_FROM" ]; then
    GIT_SRC="$GIT_FROM"
  elif [ -f .git ]; then
    GIT_SRC="$(sed -n 's/^gitdir: //p' .git | head -1 | tr -d '\n')"
  elif [ -d .git ]; then
    GIT_SRC=".git"
  fi
  if [ -z "$GIT_SRC" ] || [ ! -d "$GIT_SRC" ]; then
    echo "WARN: no .git directory found at '$GIT_SRC' — packing working tree only." >&2
    EXCLUDES+=(--exclude=".git" --exclude=".git/**")
  fi
fi

# Safety scan: refuse to pack files that match known credential patterns.
mapfile -t all_files < <(tar -cf - "${EXCLUDES[@]}" . 2>/dev/null | tar -tf - | sort -u)
echo "Scanning $(printf '%s\n' "${all_files[@]}" | wc -l) files for credentials before packing..."
SECRETS_FOUND=0
for f in "${all_files[@]}"; do
  case "$f" in
    */|'') continue ;;
  esac
  if [ -L "$f" ]; then continue; fi
  case "$f" in
    *.png|*.jpg|*.jpeg|*.webp|*.gif|*.ctex|*.ttf|*.otf|*.woff|*.woff2|*.ico) continue ;;
  esac
  if [ ! -r "$f" ]; then continue; fi
  if grep -IqE 'ghp_[A-Za-z0-9]{30,}|gho_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|sk-[A-Za-z0-9]{20,}|sk_live_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|ya29\.[0-9A-Za-z_-]{30,}|glpat-[A-Za-z0-9_-]{20,}|glptt-[A-Za-z0-9_-]{20,}' "$f" 2>/dev/null; then
    echo "ERROR: $f contains a credential-shaped string. Refusing to pack." >&2
    SECRETS_FOUND=1
  fi
done
if [ "$SECRETS_FOUND" -ne 0 ]; then
  echo "Pack aborted. Scrub the listed files and retry." >&2
  exit 1
fi

echo "Creating archive: $OUT"
if [ -n "$GIT_SRC" ] && [ -d "$GIT_SRC" ]; then
  echo "  (git history: from $GIT_SRC)"
  # Build a temp dir with the working tree + real .git/, then tar.
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  tar -cf - "${EXCLUDES[@]}" . | (cd "$tmpdir" && tar -xf -)
  rm -f "$tmpdir/.git"
  cp -a "$GIT_SRC" "$tmpdir/.git"
  tar -czf "$OUT" -C "$tmpdir" .
else
  tar -czf "$OUT" "${EXCLUDES[@]}" .
fi

# Report what was packed.
size=$(du -h "$OUT" | cut -f1)
files=$(tar -tzf "$OUT" 2>/dev/null | grep -v '/$' | wc -l)
echo "Done: $OUT ($size, $files files)"
echo ""
echo "Next step: copy this file to your machine, then run"
echo "           scripts/unpack_repo.sh /path/to/$OUT --push-to /path/to/your/local-remote.git"

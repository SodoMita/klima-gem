#!/usr/bin/env bash
# unpack_repo.sh — extract a Chrono Nexus repo archive and either:
#   (a) dump it to /tmp/chrono-nexus-extracted-*/  (default)
#   (b) "push" it to a local bare git repo at a path you specify,
#       so your local repo can `git fetch` from it just like a real
#       GitHub push.
#
# Usage:
#   scripts/unpack_repo.sh <archive.tar.gz>                       # extract to /tmp
#   scripts/unpack_repo.sh <archive.tar.gz> --push-to <path.git>  # push to local bare repo
#   scripts/unpack_repo.sh <archive.tar.gz> --into <dir>          # extract into a specific dir
#   scripts/unpack_repo.sh <archive.tar.gz> --into-existing <repo> # sync into existing repo
#
#   --push-to <path>     Create a bare git repo at <path>, then
#                        commit the working tree as a single
#                        squashed commit and `git push` it. Your
#                        local clone can then:
#                          git remote add chrono file://<path>
#                          git fetch chrono
#                          git reset --hard chrono/main
#
#   --into-existing <existing-repo>
#                        Copy the unpacked files into an EXISTING
#                        non-bare git repository, backing up any
#                        conflicting files and running `git add -A`
#                        so you can review with `git status` /
#                        `git diff --cached` and `git commit` (or
#                        `git reset` to abort). This is the right
#                        mode for syncing into a long-lived local
#                        repo that already has its own history.
#                        Example:
#                          scripts/unpack_repo.sh archive.tgz \
#                              --into-existing /home/hobo2/Godots/suxen-sonorhc
#
#   --keep-history       Don't squash — push each commit as a real
#                        ref so `git log` shows the full history.
#                        (Only meaningful with --push-to.)
#   --into <dir>         Extract to <dir> instead of /tmp.
#   --keep-git           Also extract the .git/ directory.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ARCHIVE=""
PUSH_TO=""
INTO=""
INTO_EXISTING=""
KEEP_GIT=0
KEEP_HISTORY=0
PUSH_WORK=""
INCOMING=""

while [ $# -gt 0 ]; do
  case "$1" in
    --push-to) PUSH_TO="$2"; shift 2 ;;
    --into) INTO="$2"; shift 2 ;;
    --into-existing) INTO_EXISTING="$2"; shift 2 ;;
    --keep-git) KEEP_GIT=1; shift ;;
    --keep-history) KEEP_HISTORY=1; shift ;;
    -h|--help)
      sed -n '2,30p' "$0"
      exit 0
      ;;
    *) ARCHIVE="$1"; shift ;;
  esac
done

if [ -z "$ARCHIVE" ]; then
  echo "Usage: $0 <archive.tar.gz> [--push-to <path.git>] [--into <dir>]" >&2
  echo "       [--into-existing <existing-repo>] [--keep-git] [--keep-history]" >&2
  exit 2
fi
if [ ! -f "$ARCHIVE" ]; then
  echo "ERROR: archive not found: $ARCHIVE" >&2
  exit 2
fi

# Pick the destination directory.
if [ -n "$INTO" ]; then
  DEST="$INTO"
elif [ -n "$PUSH_TO" ]; then
  DEST="$(mktemp -d -t chrono-nexus-unpack-XXXXXX)"
else
  DEST="/tmp/chrono-nexus-extracted-$(date -u +%Y%m%d-%H%M%S)"
fi
mkdir -p "$DEST"
echo "Extracting $ARCHIVE to $DEST"

# List the contents first so the user can review.
echo ""
echo "=== Archive contents (first 40 entries) ==="
tar -tzf "$ARCHIVE" 2>/dev/null | head -40 || true
total=$(tar -tzf "$ARCHIVE" 2>/dev/null | wc -l || echo 0)
echo "... ($total entries total)"
echo ""

# Decide whether to include .git in the extraction.
if [ "$KEEP_GIT" -eq 0 ]; then
  echo "(Stripping .git/ from the archive. Use --keep-git to include it.)"
  tar -xzf "$ARCHIVE" -C "$DEST" --exclude=".git"
else
  tar -xzf "$ARCHIVE" -C "$DEST"
fi

# Sanity check.
echo ""
echo "=== Sanity check ==="
ls -A "$DEST" 2>/dev/null | head -20
test -d "$DEST/.git" && echo "(.git/ present)" || echo "(.git/ not present)"
test -f "$DEST/GameState.gd" && echo "OK: GameState.gd present"
test -f "$DEST/main.gd" && echo "OK: main.gd present"
test -f "$DEST/scripts/pack_repo.sh" && echo "OK: pack_repo.sh present"
echo ""

# If --push-to, create the bare repo and push.
if [ -n "$PUSH_TO" ]; then
  PUSH_TO_ABS="$(cd "$(dirname "$PUSH_TO")" 2>/dev/null && pwd)/$(basename "$PUSH_TO")"
  if [ -e "$PUSH_TO_ABS" ]; then
    if [ -d "$PUSH_TO_ABS" ] && [ -d "$PUSH_TO_ABS/refs" ] && [ -d "$PUSH_TO_ABS/objects" ]; then
      echo "Bare repo already exists at $PUSH_TO_ABS. Re-using (will force-push)."
    else
      echo "ERROR: $PUSH_TO_ABS already exists but is not a bare git repo. Aborting." >&2
      exit 1
    fi
  else
    mkdir -p "$(dirname "$PUSH_TO_ABS")"
    git init --bare -b main "$PUSH_TO_ABS" >/dev/null
    echo "Created bare repo: $PUSH_TO_ABS"
  fi

  PUSH_WORK="$(mktemp -d -t chrono-nexus-pushwork-XXXXXX)"
  cleanup_push() {
    [ -n "${PUSH_WORK:-}" ] && [ -d "$PUSH_WORK" ] && rm -rf "$PUSH_WORK"
  }
  trap cleanup_push EXIT
  git clone "$PUSH_TO_ABS" "$PUSH_WORK" >/dev/null 2>&1

  cd "$PUSH_WORK"
  git config user.email "agent@local"
  git config user.name "Agent"

  if [ "$KEEP_HISTORY" -eq 1 ] && [ -d "$DEST/.git" ]; then
    # Real history: replace .git with the archive's, preserving origin.
    echo "Pushing real git history from the archive..."
    origin_url="$(git config --get remote.origin.url || true)"
    origin_fetch="$(git config --get remote.origin.fetch || true)"
    rm -rf .git
    cp -a "$DEST/.git" .
    if [ -n "$origin_url" ]; then
      git remote remove origin 2>/dev/null || true
      git remote add origin "$origin_url"
      [ -n "$origin_fetch" ] && git config remote.origin.fetch "$origin_fetch"
    fi
    git checkout -- . 2>/dev/null || true
    local_branch="$(git for-each-ref --format='%(refname:short)' refs/heads/ | head -1)"
    if [ -z "$local_branch" ]; then
      echo "ERROR: no local branch found after replacing .git. Aborting." >&2
      cd "$ROOT"; exit 1
    fi
    git push --force origin "$local_branch:main"
  else
    # Squashed single commit: copy files, commit, push.
    echo "Pushing squashed single commit..."
    find . -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
    cp -a "$DEST"/. ./
    git add -A
    if git diff --cached --quiet; then
      echo "WARN: nothing to commit - working tree identical to remote." >&2
    else
      git commit -m "Sync from pack_repo.sh $(date -u +%Y%m%d-%H%M%S)

Squashed commit of the working tree at archive time." >/dev/null
      git push --force origin main
    fi
  fi
  cd "$ROOT"

  file_url="file://$PUSH_TO_ABS"
  echo ""
  echo "================================================================="
  echo "PUSH COMPLETE"
  echo "================================================================="
  echo ""
  echo "Local bare 'remote': $PUSH_TO_ABS"
  echo "Fetch URL (file://): $file_url"
  echo ""
  echo "On your machine, in your local clone of chrono-nexus-godot:"
  echo ""
  echo "  # one-time setup: add the local remote"
  echo "  git remote add chrono $file_url"
  echo ""
  echo "  # every sync: fetch + reset to match (like a real GitHub push)"
  echo "  git fetch chrono"
  echo "  git reset --hard chrono/main"
  echo ""
  echo "  # or, if you want to keep your local commits and rebase:"
  echo "  git fetch chrono"
  echo "  git rebase chrono/main"
  echo ""
  exit 0
fi



# === --into-existing mode ===
# Added per user request: unpack into a random /tmp dir, then copy
# the working tree into an EXISTING non-bare repo. Do NOT force-push,
# do NOT reset the user's commits. Just stage the new files so the
# user can review (git status / git diff --cached) and commit or
# reset as they see fit.
#
# This is the right mode for syncing into a long-lived local repo
# that already has its own history (e.g. /home/hobo2/Godots/suxen-
# sonorhc, which the user keeps separate from the agent's sandbox).

if [ -n "${INTO_EXISTING:-}" ]; then
  TARGET_ABS="$(cd "$INTO_EXISTING" 2>/dev/null && pwd)"
  if [ -z "$TARGET_ABS" ]; then
    echo "ERROR: --into-existing target does not exist: $INTO_EXISTING" >&2
    exit 2
  fi
  if [ ! -d "$TARGET_ABS/.git" ]; then
    echo "ERROR: $TARGET_ABS exists but is not a git repository (no .git)." >&2
    echo "       Use --into <dir> for a plain extraction, or --push-to <path.git> for a bare repo." >&2
    exit 2
  fi

  INCOMING="$(mktemp -d -t chrono-nexus-incoming-XXXXXX)"
  # Set up cleanup. Use a function so `set -u` doesn't trip on
  # variables that may or may not be set in this branch.
  cleanup_incoming() {
    [ -n "${INCOMING:-}" ] && [ -d "$INCOMING" ] && rm -rf "$INCOMING"
    [ -n "${PUSH_WORK:-}" ] && [ -d "$PUSH_WORK" ] && rm -rf "$PUSH_WORK"
  }
  trap cleanup_incoming EXIT

  # Re-extract the archive into a fresh incoming dir. We always
  # re-extract here (the previous extraction went to $DEST, which
  # may have been a /tmp dir we made for the push flow).
  rm -rf "$INCOMING"
  mkdir -p "$INCOMING"
  if [ "$KEEP_GIT" -eq 0 ]; then
    tar -xzf "$ARCHIVE" -C "$INCOMING" --exclude=".git"
  else
    tar -xzf "$ARCHIVE" -C "$INCOMING"
  fi

  echo ""
  echo "================================================================="
  echo "SYNCING INTO EXISTING REPO"
  echo "================================================================="
  echo ""
  echo "Incoming working tree: $INCOMING"
  echo "Target repo:           $TARGET_ABS"
  echo ""
  echo "This will copy the incoming files into the target repo and"
  echo "stage them with 'git add -A'. Your existing commits in the"
  echo "target repo are NOT touched. Review with 'git status' / 'git"
  echo "diff --cached' and then 'git commit' (or 'git reset' to abort)."
  echo ""

  # Copy incoming files into the target repo, overwriting any
  # conflicts (but backing up the user's local files first so they
  # can recover if needed).
  BACKUP_DIR="$TARGET_ABS/.chrono-nexus-incoming-backup-$(date -u +%Y%m%d-%H%M%S)"
  echo "If any files in the target would be overwritten, the originals"
  echo "are saved to: $BACKUP_DIR"
  echo ""

  cd "$TARGET_ABS"
  copied=0
  backed_up=0
  # Only iterate over FILES. Directories are created automatically
  # by `mkdir -p` before each copy. (Previously we iterated over
  # everything, including directory entries, which made `cp -a
  # $src $dst` recurse: the source dir got copied INTO the
  # destination, creating `$dst/$dst/...` paths.)
  while IFS= read -r -d '' src; do
    [ ! -f "$src" ] && continue
    rel="${src#$INCOMING/}"
    if [ "$rel" = ".git" ] || [ "$rel" = ".git/" ]; then continue; fi
    if [ -e "$TARGET_ABS/$rel" ]; then
      if [ ! -d "$BACKUP_DIR" ]; then mkdir -p "$BACKUP_DIR"; fi
      mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
      cp -a "$TARGET_ABS/$rel" "$BACKUP_DIR/$rel"
      backed_up=$((backed_up + 1))
    fi
    mkdir -p "$TARGET_ABS/$(dirname "$rel")"
    cp -a "$src" "$TARGET_ABS/$rel"
    copied=$((copied + 1))
  done < <(find "$INCOMING" -mindepth 1 -type f -print0)

  echo "Copied: $copied files"
  if [ "$backed_up" -gt 0 ]; then
    echo "Backed up (replaced): $backed_up files -> $BACKUP_DIR"
  fi
  echo ""

  # Stage all changes in the target repo. We also stage the
  # backup dir but then unstage it (the user can review what's
  # about to be committed without the backup cluttering the
  # output). The backup dir is also added to .gitignore so future
  # `git add -A` calls don't pick it up either.
  if [ "$backed_up" -gt 0 ]; then
    # Append the backup dir to .gitignore if it isn't already there.
    if [ -f "$TARGET_ABS/.gitignore" ] && ! grep -qxF "/.chrono-nexus-incoming-backup-*/" "$TARGET_ABS/.gitignore"; then
      printf '\n# Ignore backups created by chrono-nexus unpack --into-existing\n/.chrono-nexus-incoming-backup-*/\n' >> "$TARGET_ABS/.gitignore"
    elif [ ! -f "$TARGET_ABS/.gitignore" ]; then
      printf '# Ignore backups created by chrono-nexus unpack --into-existing\n/.chrono-nexus-incoming-backup-*/\n' > "$TARGET_ABS/.gitignore"
    fi
  fi
  git add -A
  echo "Staged. Run in $TARGET_ABS:"
  echo ""
  echo "  git status                  # see what would change"
  echo "  git diff --cached --stat    # see the size of the incoming patch"
  echo "  git commit -m 'Sync from chrono-nexus pack'"
  echo "  # or, to abort and roll back the copies:"
  echo "  git reset                    # un-stage, keep working tree"
  echo "  rsync -a --delete $BACKUP_DIR/ ./  # restore originals"
  echo ""
  exit 0
fi

# Default mode: just extracted, no push.
echo ""
echo "Done. Unpacked to: $DEST"
echo ""
echo "To merge into your local repo, run one of:"
echo ""
echo "  # Option A: keep local changes (rsync with backup)"
echo "  cd /path/to/your/local/chrono-nexus-godot"
echo "  rsync -a --backup --backup-dir=.chrono-nexus-backup-\$(date +%s) \\"
echo "      $DEST/ ./"
echo "  git add -A"
echo ""
echo "  # Option B: discard local changes"
echo "  rsync -a --delete $DEST/ ./"
echo "  git add -A"
echo ""
echo "  # Option C: re-pack with --push-to for a real local 'remote'"
echo "  scripts/unpack_repo.sh $ARCHIVE --push-to ~/chrono-nexus-remote.git"

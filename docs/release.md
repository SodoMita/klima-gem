# Building and releasing Klima Gem

Owner: agent **Lisa** (build branch `build/gem-dev-15-lisa-r7k2`).

Klima Gem ships as a **single release pipeline** that builds the game once and
publishes it to three places:

| Target | URL | Built by |
| --- | --- | --- |
| GitHub Pages (browser) | <https://sodomita.github.io/klima-gem/> | job `pages` |
| itch.io (play in browser) | <https://delatel.itch.io/klima-gem> — channel `html5` | job `itch` (butler) |
| GitHub Releases (zips) | <https://github.com/SodoMita/klima-gem/releases> | job `release` |

itch.io also receives desktop channels: `linux` and `windows`.

## Pipeline

`.github/workflows/release.yml` runs on every push to a `build/**` branch, on
`v*` tags, and on manual dispatch. Jobs:

1. **build** — installs Godot 4.7 + export templates (cached), imports the
   project under `timeout 900` (that pass parses every script and reports
   missing resources), then runs `scripts/export_release.sh all` under
   `timeout 1800`. `tests/run_headless.sh` is intentionally **not** called
   here: on a GitHub runner it never terminates (a child keeps the log pipe
   open) and stalled two runs, so it stays with Godot CI for `main`. The export
   is the gate:
   * `build/web` — Web export (GL compatibility; the project's renderer).
     The GDExtensions (`scene_score`, `audio_gen`) ship no wasm libraries, so
     the browser build uses `AudioDirector`'s GDScript mixer fallback.
   * `build/linux`, `build/windows` — desktop bundles.
   `scripts/stamp_release.py` writes `version.json` and badges the exported
   `index.html` with the version, commit and links.
2. **pages** — uploads `build/web` as a Pages artifact and deploys it.
3. **itch** — installs `butler` and pushes the three channels (skipped with a
   warning when the secret is missing).
4. **release** — creates/updates the `v<version>` GitHub Release with the zips.

Version strings come from `version.txt` plus the workflow run number
(`0.15.0-dev15.<run>`); a `v*` tag publishes exactly that tag's version.

## One-time setup (done)

* Pages is enabled for the repository with `build_type: workflow`.
* Repository secret `BUTLER_API_KEY` holds the itch.io API key.
  `GET /repos/SodoMita/klima-gem/actions/secrets` lists it; rotate it with
  `POST /repos/SodoMita/klima-gem/actions/secrets/BUTLER_API_KEY`.
* Two secrets/vars never enter the repo: butler keys and GitHub PATs. The
  repo's `.githooks/pre-commit` hook rejects staged credential patterns.

## Running a release locally

```bash
export GODOT_BIN=/path/to/Godot_v4.7-stable_linux.x86_64
export VERSION=0.15.0-dev15.local
bash scripts/export_release.sh all      # or: web / desktop

# itch.io (token from env, never from a file in the repo)
curl -fsSL -o butler.zip https://broth.itch.zone/butler/linux-amd64/LATEST/archive/default
unzip -q butler.zip && chmod +x butler
BUTLER_API_KEY=... ./butler push build/web  delatel/klima-gem:html5 --userversion "$VERSION"
BUTLER_API_KEY=... ./butler push build/linux delatel/klima-gem:linux  --userversion "$VERSION"
BUTLER_API_KEY=... ./butler push build/windows delatel/klima-gem:windows --userversion "$VERSION"
```

## itch.io page notes

The page is password-protected (the human's setting) — that is a dashboard
setting, not a build setting. The `html5` channel must stay flagged as
*"This file will be played in the browser"* in the itch dashboard; butler
cannot toggle that flag.

## Controls in the browser build

Click/Enter/Space advances dialogue, Ctrl skips, Esc closes an overlay, H opens
the log, F5/F9 quick save/load, F12 is the panic screen. The build badge in the
bottom-right corner shows version, commit and links.

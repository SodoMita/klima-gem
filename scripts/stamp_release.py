#!/usr/bin/env python3
"""Stamp a Klima Gem export with its release identity.

Writes <build_dir>/version.json, mirrors it into build/web, and injects a small
version badge plus the itch.io / GitHub links into the exported web player so a
release can always be identified from the browser.

Usage: python3 scripts/stamp_release.py BUILD_DIR VERSION [COMMIT] [BRANCH]
"""
from __future__ import annotations

import datetime as _dt
import json
import pathlib
import re
import sys

PAGES_URL = "https://sodomita.github.io/klima-gem/"
ITCH_URL = "https://delatel.itch.io/klima-gem"
REPO_URL = "https://github.com/SodoMita/klima-gem"


def main(argv: list[str]) -> int:
    build_dir = pathlib.Path(argv[1] if len(argv) > 1 else "build")
    version = argv[2] if len(argv) > 2 else "0.0.0-dev"
    commit = argv[3] if len(argv) > 3 else "local"
    branch = argv[4] if len(argv) > 4 else "local"

    build_dir.mkdir(parents=True, exist_ok=True)
    stamp = {
        "game": "Klima Gem",
        "version": version,
        "commit": commit,
        "branch": branch,
        "built_at": _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "pages_url": PAGES_URL,
        "itch_url": ITCH_URL,
        "repo_url": REPO_URL,
    }
    text = json.dumps(stamp, indent=2) + "\n"
    (build_dir / "version.json").write_text(text, encoding="utf-8")

    web_dir = build_dir / "web"
    index = web_dir / "index.html"
    (web_dir / "version.json").write_text(text, encoding="utf-8") if web_dir.is_dir() else None
    if not index.is_file():
        print(f"stamp: no web player at {index}, wrote {build_dir / 'version.json'}")
        return 0

    html = index.read_text(encoding="utf-8")
    title = f"Klima Gem {version}"
    html = re.sub(r"<title>.*?</title>", f"<title>{title}</title>", html, count=1, flags=re.S)
    html = re.sub(
        r'(<meta name="description" content=")[^"]*(")',
        rf"\1Klima Gem build {version} ({commit[:8]}) — play in the browser.\2",
        html,
        count=1,
    )

    badge = f"""
		<div id="klima-build-badge" style="position:fixed;right:10px;bottom:10px;z-index:99;
			font:12px/1.4 system-ui,-apple-system,'Segoe UI',sans-serif;color:#dff6ff;
			background:rgba(6,18,28,.72);border:1px solid rgba(120,220,255,.35);border-radius:8px;
			padding:6px 10px;backdrop-filter:blur(6px);pointer-events:auto">
			<b>Klima Gem</b> {version} · {commit[:8]}
			&nbsp;<a href="{ITCH_URL}" style="color:#8fe3ff">itch</a>
			&nbsp;<a href="{REPO_URL}" style="color:#8fe3ff">github</a>
		</div>
	</body>"""
    if "klima-build-badge" not in html and "</body>" in html:
        html = html.replace("</body>", badge, 1)
    index.write_text(html, encoding="utf-8")
    print(f"stamp: {index} -> {title} ({commit[:8]} on {branch})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

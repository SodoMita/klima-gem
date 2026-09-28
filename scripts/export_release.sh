#!/usr/bin/env bash
# Klima Gem — release export driver (used locally and by .github/workflows/release.yml).
#
#   scripts/export_release.sh web       # build/web  -> GitHub Pages + itch html5
#   scripts/export_release.sh desktop   # build/linux, build/windows -> itch + release assets
#   scripts/export_release.sh all
#
# Env: GODOT_BIN (default: godot), VERSION, BUILD_DIR (default: build)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

GODOT_BIN="${GODOT_BIN:-godot}"
BUILD_DIR="${BUILD_DIR:-build}"
VERSION="${VERSION:-$(cat version.txt 2>/dev/null || echo 0.0.0-dev)}"
WHAT="${1:-all}"

if [ ! -x "$GODOT_BIN" ] && ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
	echo "ERROR: Godot binary not found ($GODOT_BIN). Set GODOT_BIN=/path/to/godot" >&2
	exit 1
fi

echo "=== Klima Gem release export ==="
echo "Godot  : $GODOT_BIN ($("$GODOT_BIN" --version))"
echo "Version: $VERSION"
echo "Target : $WHAT"

export_web() {
	echo ""
	echo "--- Web (GitHub Pages + itch html5) ---"
	mkdir -p "$BUILD_DIR/web"
	"$GODOT_BIN" --headless --export-release "Web" "$BUILD_DIR/web/index.html"
	test -f "$BUILD_DIR/web/index.html" || { echo "ERROR: web export produced no index.html" >&2; exit 1; }
	test -f "$BUILD_DIR/web/index.wasm" || { echo "ERROR: web export produced no index.wasm" >&2; exit 1; }
	# The C audio engines MUST ship as wasm side modules (chat msgs 136-139:
	# an export with gdextensionLibs:[] plays the wrong music). Fail loudly.
	grep -q "libaudio_gen.web.wasm32" "$BUILD_DIR/web/index.html" || {
		echo "ERROR: web export has no AudioGen wasm in gdextensionLibs — extensions_support off or wasm missing" >&2; exit 1; }
	grep -q "libscene_score.web.wasm32" "$BUILD_DIR/web/index.html" || {
		echo "ERROR: web export has no SceneScore wasm in gdextensionLibs" >&2; exit 1; }
	ls -l "$BUILD_DIR/web"
}

export_desktop() {
	echo ""
	echo "--- Linux ---"
	mkdir -p "$BUILD_DIR/linux"
	"$GODOT_BIN" --headless --export-release "Linux" "$BUILD_DIR/linux/klima-gem.x86_64"
	chmod +x "$BUILD_DIR/linux/klima-gem.x86_64" || true
	echo "--- Windows ---"
	mkdir -p "$BUILD_DIR/windows"
	"$GODOT_BIN" --headless --export-release "Windows Desktop" "$BUILD_DIR/windows/klima-gem.exe"
	ls -l "$BUILD_DIR/linux" "$BUILD_DIR/windows"
}

case "$WHAT" in
	web) export_web ;;
	desktop) export_desktop ;;
	all) export_web; export_desktop ;;
	*) echo "ERROR: unknown target '$WHAT' (web|desktop|all)" >&2; exit 2 ;;
esac

python3 scripts/stamp_release.py "$BUILD_DIR" "$VERSION" "${GITHUB_SHA:-local}" "${GITHUB_REF_NAME:-local}"

echo ""
echo "=== export done: $BUILD_DIR ==="
find "$BUILD_DIR" -maxdepth 2 -type f | sort | head -40

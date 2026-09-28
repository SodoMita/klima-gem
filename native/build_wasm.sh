#!/usr/bin/env bash
# Build the AudioGen + SceneScore GDExtensions as wasm32 SIDE MODULEs for the
# Web export (chat msg 138: no GDScript audio on web — the C engines run as
# WASM). Requires an activated emsdk (emcc on PATH).
#
#   source /path/to/emsdk/emsdk_env.sh
#   bash native/build_wasm.sh
#
# Two variants per library, matching the official export templates:
#   *.web.wasm32.nothreads.wasm  -> "Thread Support" OFF (GitHub Pages / itch:
#                                   no COOP/COEP headers, this is the deployed one)
#   *.web.wasm32.wasm            -> "Thread Support" ON (needs cross-origin isolation)
# The export template must be a *dlink* variant: enabled by
# variant/extensions_support=true in export_presets.cfg — the official
# templates .tpz already ships web_dlink_*; no custom template build needed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EMCC="${EMCC:-emcc}"
command -v "$EMCC" >/dev/null 2>&1 || { echo "ERROR: emcc not found — source emsdk_env.sh first" >&2; exit 1; }
echo "emcc: $("$EMCC" --version | head -1)"

AG="$ROOT/native/audio_gen"
SS="$ROOT/native/scene_score"

AG_SRCS="$(printf '%s ' "$AG"/src/*.c) $AG/gdext/audio_gen_gde.c"
SS_SRCS="$SS/gde.c $SS/mix.c"

CFLAGS_COMMON="-std=c11 -O2 -fvisibility=hidden -sSIDE_MODULE=1 -sSUPPORT_LONGJMP=wasm"

build() { # build <out.wasm> <extra-cflags> <includes...> -- <srcs>
	local out="$1"; shift
	local extra="$1"; shift
	echo "--- $(basename "$out")"
	# shellcheck disable=SC2086
	"$EMCC" $CFLAGS_COMMON $extra "$@" -o "$out"
}

mkdir -p "$ROOT/addons/audio_gen/bin" "$ROOT/addons/scene_score/bin"

build "$ROOT/addons/audio_gen/bin/libaudio_gen.web.wasm32.nothreads.wasm" "" \
	-I "$AG/include" -I "$SS" $AG_SRCS
build "$ROOT/addons/audio_gen/bin/libaudio_gen.web.wasm32.wasm" "-pthread" \
	-I "$AG/include" -I "$SS" $AG_SRCS
build "$ROOT/addons/scene_score/bin/libscene_score.web.wasm32.nothreads.wasm" "" \
	-I "$SS" $SS_SRCS
build "$ROOT/addons/scene_score/bin/libscene_score.web.wasm32.wasm" "-pthread" \
	-I "$SS" $SS_SRCS

ls -lh "$ROOT"/addons/audio_gen/bin/*.wasm "$ROOT"/addons/scene_score/bin/*.wasm
echo "wasm side modules built"

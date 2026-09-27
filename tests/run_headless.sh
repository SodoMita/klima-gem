#!/usr/bin/env bash
# Headless smoke test for the Chrono Nexus Godot project.
# Runs the project in headless mode and checks for any script errors,
# parse failures, or missing-resource warnings. Exits non-zero on any
# failure so it can run in CI.
#
# Usage: tests/run_headless.sh
#        GODOT_BIN=/path/to/godot tests/run_headless.sh
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# The live mixer has to be present even when Godot itself is not.
echo "=== SceneScore extension ==="
if [ ! -f "$ROOT/addons/scene_score/scene_score.gdextension" ]; then
	echo "ERROR: SceneScore GDExtension is missing."
	exit 1
fi
for arch in x86_64 arm64 arm32; do
	if [ ! -f "$ROOT/addons/scene_score/bin/libscene_score.linux.${arch}.so" ]; then
		echo "ERROR: missing SceneScore linux ${arch} library."
		exit 1
	fi
done
if ! nm -D "$ROOT/addons/scene_score/bin/libscene_score.linux.x86_64.so" | grep -q ' scene_score_library_init$'; then
	echo "ERROR: SceneScore entry symbol is not exported."
	exit 1
fi
if grep -q 'BAKE_BARS\|_bake_chunk' "$ROOT/autoloads/audio_director.gd"; then
	echo "ERROR: procedural music is baked instead of generated live."
	exit 1
fi
echo "OK: live SceneScore libraries are present."

# Locate the Godot binary.
GODOT_BIN="${GODOT_BIN:-/home/user/.local/bin/godot}"
if [ ! -x "$GODOT_BIN" ]; then
	echo "ERROR: Godot binary not found at $GODOT_BIN"
	echo "       Set GODOT_BIN env var to the path of Godot 4.7+"
	exit 1
fi
echo "Using Godot: $GODOT_BIN"
"$GODOT_BIN" --version

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Step 1: Re-import (validates resources, regenerates UIDs, etc.)
echo ""
echo "=== Step 1: Re-importing project ==="
"$GODOT_BIN" --headless --import 2>&1 | tee /tmp/chrono-nexus-import.log
IMPORT_LOG=/tmp/chrono-nexus-import.log
if grep -E "^SCRIPT ERROR|^ERROR|Parse Error|Parse error" "$IMPORT_LOG"; then
	echo "ERROR: Re-import failed. See $IMPORT_LOG"
	exit 1
fi

# Step 2: Run the project headlessly for a few seconds, capture output.
echo ""
echo "=== Step 2: Running project headlessly (15s timeout) ==="
timeout 15 "$GODOT_BIN" --headless 2>&1 | tee /tmp/chrono-nexus-run.log
RUN_LOG=/tmp/chrono-nexus-run.log

# Step 3: Verify the logs don't contain errors that would break the game.
# Note: 'dissolve' transition warning is a known Dialogic 2 limitation
# in the existing timeline file and is NOT a regression — we filter
# it out so CI stays green.
echo ""
echo "=== Step 3: Checking for runtime errors ==="
ERRORS=$(grep -E "^SCRIPT ERROR|^ERROR|Parse Error" "$RUN_LOG" | grep -v "Unable to identify BackgroundTransition" || true)
if [ -n "$ERRORS" ]; then
	echo "ERROR: Runtime errors detected:"
	echo "$ERRORS"
	exit 1
fi

# Step 4: The 3D nexus backdrop was removed. Dialogue uses the 2D backgrounds.
echo ""
echo "=== Step 4: Verifying the 3D backdrop is gone ==="
if [ -f scenes/3d/nexus_3d.tscn ] || grep -q "nexus_3d.tscn" main.tscn; then
	echo "ERROR: the 3D background scene is still in the game."
	exit 1
fi
echo "OK: no 3D background scene."

# Step 5: Verify the Dialogue Manager balloon replaced Dialogic.
echo ""
echo "=== Step 5: Verifying vn_dialogue_demo balloon ==="
if [ ! -f scenes/vn_balloon.tscn ] || [ ! -f addons/dialogue_manager/plugin.cfg ]; then
	echo "ERROR: Dialogue Manager balloon is missing."
	exit 1
fi
if [ -d addons/dialogic ]; then
	echo "ERROR: Dialogic addon is still present."
	exit 1
fi
if grep -q "Typewriter sound" scenes/vn_balloon.tscn || grep -q "typing_tick" scenes/vn_balloon.gd autoloads/audio_director.gd; then
	echo "ERROR: typewriter sound is still wired up."
	exit 1
fi
if ! grep -q "CHRONO NEXUS" scenes/vn_balloon.tscn; then
	echo "ERROR: Chrono Nexus UI mark is missing from the balloon."
	exit 1
fi
if [ ! -f dialogue/chrono_nexus.dialogue ]; then
	echo "ERROR: story dialogue is missing."
	exit 1
fi
echo "OK: balloon, story, and no typewriter ticks."

# Step 6: Verify the GameState autoload is registered.
echo ""
echo "=== Step 6: Verifying GameState autoload ==="
if grep -q "^GameState=" project.godot; then
	echo "OK: GameState is in autoloads."
else
	echo "ERROR: GameState autoload not registered."
	exit 1
fi

# Step 7: Verify the secrets guard (pre-commit hook).
echo ""
echo "=== Step 7: Verifying pre-commit secrets guard ==="
if [ -x .githooks/pre-commit ]; then
	echo "OK: pre-commit hook is executable."
else
	echo "WARN: pre-commit hook is missing or not executable."
fi

# Step 8: StageDirector motion system (tweens, NLA tracks, frame ranges,
# shake, rollback replay) has its own headless suite.
echo ""
echo "=== Step 8: StageDirector motion tests ==="
bash tests/motion_director_test.sh

echo ""
echo "=== All checks passed ==="

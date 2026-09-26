#!/usr/bin/env bash
# Window-level checks for the resolution setting.
#
# These are not part of tests/run_headless.sh on purpose: headless has no
# window, and the setting used to fail only under a window manager (a
# maximized or fullscreen window owns its size and drops the request). So this
# script runs the game under Xvfb with openbox, on two screen sizes, and
# measures the window from outside the process with xdotool.
#
# Usage: tests/resolution_window_test.sh
#        GODOT_BIN=/path/to/godot tests/resolution_window_test.sh
#
# Needs: xvfb, openbox, xdotool
#        (apt-get install -y xvfb openbox xdotool)
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/home/user/.local/bin/godot}"
SCREENS="${SCREENS:-1920x1080 1366x768}"
TITLE="Chrono Nexus"

if [ ! -x "$GODOT_BIN" ]; then
	echo "ERROR: Godot not found at $GODOT_BIN (set GODOT_BIN)." >&2
	exit 1
fi
for bin in xvfb-run openbox xdotool; do
	if ! command -v "$bin" >/dev/null 2>&1; then
		echo "SKIP: $bin is not installed; cannot check window behaviour."
		echo "      apt-get install -y xvfb openbox xdotool"
		exit 0
	fi
done

cd "$ROOT"
echo "Using Godot: $GODOT_BIN ($("$GODOT_BIN" --version))"

# A private HOME keeps the run hermetic: settings live in
# $HOME/.local/share/godot/app_userdata/<project name>/.
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
SETTINGS_DIR="$SANDBOX/.local/share/godot/app_userdata/$TITLE/chrono_nexus"

failures=0

saved_settings() {   # saved_settings <res_w> <res_h>
	mkdir -p "$SETTINGS_DIR"
	printf '{"res_w": %s, "res_h": %s, "fullscreen": false}\n' "$1" "$2" > "$SETTINGS_DIR/settings.json"
}

# The harness scene drives the panel; run_in_window reports PASS/FAIL lines.
panel_checks() {     # panel_checks <screen>
	local screen="$1" log
	log="$(mktemp)"
	HOME="$SANDBOX" timeout 120 xvfb-run -a -s "-screen 0 ${screen}x24" bash -c "
		openbox --sm-disable >/dev/null 2>&1 &
		sleep 2
		exec '$GODOT_BIN' --rendering-driver opengl3 res://tests/resolution_window_e2e.tscn
	" > "$log" 2>&1
	local rc=$?
	local passed failed
	passed="$(grep -c '^PASS' "$log" || true)"
	failed="$(grep -c '^FAIL' "$log" || true)"
	echo "--- panel checks on $screen: $passed passed, $failed failed (exit $rc)"
	grep '^FAIL' "$log" | sed 's/^/    /'
	grep -E 'SCRIPT ERROR|Parse Error' "$log" | head -5 | sed 's/^/    /'
	failures=$((failures + failed))
	if [ "$failed" = "0" ] && [ "$passed" -lt 15 ]; then
		echo "    ERROR: the harness stopped early (no failures but too few checks)."
		failures=$((failures + 1))
	fi
	rm -f "$log"
}

# The window the game actually opens with, measured by the WM.
booted_window() {    # booted_window <screen>
	local screen="$1"
	HOME="$SANDBOX" timeout 90 xvfb-run -a -s "-screen 0 ${screen}x24" bash -c "
		openbox --sm-disable >/dev/null 2>&1 &
		sleep 2
		'$GODOT_BIN' --rendering-driver opengl3 res://main.tscn >/dev/null 2>&1 &
		GAME=\$!
		sleep 7
		ID=\$(xdotool search --name '$TITLE' | head -1)
		if [ -n \"\$ID\" ]; then
			xdotool getwindowgeometry --shell \"\$ID\" | sed -n 's/^WIDTH=//p;s/^HEIGHT=//p' | paste -sd x
		fi
		kill \$GAME 2>/dev/null
	" 2>/dev/null | tail -1
	}

check_window() {     # check_window <label> <want> <got>
	if [ "$3" = "$2" ]; then
		echo "--- $1: $3  OK"
	else
		echo "--- $1: $3  expected $2  FAIL"
		failures=$((failures + 1))
	fi
}

for screen in $SCREENS; do
	# The harness starts from whatever is saved, so start clean.
	rm -f "$SETTINGS_DIR/settings.json"
	panel_checks "$screen"
done

# Startup has to open the title card at the saved size, fitted if the screen
# cannot show it. 1600x900 fits a 1920x1080 screen, and is fitted on 1366x768.
for screen in $SCREENS; do
	saved_settings 1600 900
	case "$screen" in
		1920x1080) want=1600x900 ;;
		1366x768)  want=1365x768 ;;
		2560x1440) want=1600x900 ;;
		*)         want=1600x900 ;;
	esac
	check_window "title card on $screen with 1600x900 saved" "$want" "$(booted_window "$screen")"
done

echo ""
if [ "$failures" -eq 0 ]; then
	echo "=== All window checks passed ==="
	exit 0
fi
echo "=== $failures window check(s) failed ==="
exit 1

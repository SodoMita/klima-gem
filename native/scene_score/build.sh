#!/bin/sh
# Build the live SceneScore GDExtension for every target this Zig can reach.
# Usage: ZIG=/path/to/zig sh native/scene_score/build.sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/native/scene_score"
OUT="$ROOT/addons/scene_score/bin"
ZIG="${ZIG:-zig}"
mkdir -p "$OUT"

compile() {
	target="$1"
	dest="$2"
	shift 2
	echo "=== $target -> $(basename "$dest") ==="
	if timeout 90 "$ZIG" cc -target "$target" -std=c11 -O2 -shared -fPIC -fvisibility=hidden \
		-I "$SRC" "$@" -o "$dest" "$SRC/gde.c" "$SRC/mix.c"; then
		return 0
	fi
	echo "FAILED $target"
	rm -f "$dest"
	return 1
}

ok=0
fail=0
note() {
	if [ "$1" -eq 0 ]; then
		ok=$((ok + 1))
	else
		fail=$((fail + 1))
	fi
}

try() {
	if compile "$@"; then
		note 0
	else
		note 1
	fi
}

try x86_64-linux-gnu.2.31 "$OUT/libscene_score.linux.x86_64.so" -lm
try x86-linux-gnu.2.31 "$OUT/libscene_score.linux.x86_32.so" -lm
try aarch64-linux-gnu.2.31 "$OUT/libscene_score.linux.arm64.so" -lm
try arm-linux-gnueabihf.2.31 "$OUT/libscene_score.linux.arm32.so" -lm
try riscv64-linux-gnu.2.31 "$OUT/libscene_score.linux.rv64.so" -lm
try x86_64-windows-gnu "$OUT/scene_score.windows.x86_64.dll"
try x86-windows-gnu "$OUT/scene_score.windows.x86_32.dll"
try aarch64-windows-gnu "$OUT/scene_score.windows.arm64.dll"
try x86_64-macos "$OUT/libscene_score.macos.x86_64.dylib" -mmacos-version-min=11.0
try aarch64-macos "$OUT/libscene_score.macos.arm64.dylib" -mmacos-version-min=11.0

# Android has no Zig libc. Link the local mem/libm (portable.c) and the stub
# headers. Do not pass -lm, and do not delete a previous binary on failure.
android() {
	target="$1"
	dest="$2"
	echo "=== $target -> $(basename "$dest") ==="
	if timeout 90 "$ZIG" cc -target "$target" -std=c11 -O2 -shared -fPIC -nostdlib \
		-fno-stack-protector -fno-builtin -fvisibility=hidden \
		-I "$SRC" -I "$SRC/stub" \
		-Wl,-z,defs -Wl,-z,max-page-size=16384 \
		-o "$dest" "$SRC/gde.c" "$SRC/mix.c" "$SRC/portable.c"; then
		note 0
	else
		echo "FAILED $target"
		note 1
	fi
}
android aarch64-linux-android "$OUT/libscene_score.android.arm64.so"
android arm-linux-androideabi "$OUT/libscene_score.android.arm32.so"
android x86_64-linux-android "$OUT/libscene_score.android.x86_64.so"
android x86-linux-android "$OUT/libscene_score.android.x86_32.so"

# iOS device needs a real libSystem.tbd (theos iPhoneOS SDK). Zig's own TBD is
# macOS-only, and the device TBD does not link the simulator. Leave an existing
# device dylib in place when the SDK is not on this machine.
if [ -n "${IOS_SDK:-}" ] && [ -f "$IOS_SDK/usr/lib/libSystem.tbd" ]; then
	ZIG_LIB="$("$ZIG" env | python3 -c 'import json,sys; print(json.load(sys.stdin)["lib_dir"])')"
	echo "=== aarch64-ios -> libscene_score.ios.arm64.dylib ==="
	if timeout 90 "$ZIG" cc -target aarch64-ios -std=c11 -O2 -shared -fPIC -nostdlib \
		-fno-stack-protector -fvisibility=hidden \
		-I "$SRC" -I "$ZIG_LIB/libc/include/any-macos-any" \
		-isysroot "$IOS_SDK" -L "$IOS_SDK/usr/lib" -lSystem \
		-o "$OUT/libscene_score.ios.arm64.dylib" "$SRC/gde.c" "$SRC/mix.c"; then
		note 0
	else
		echo "FAILED aarch64-ios"
		note 1
	fi
else
	echo "skip iOS (set IOS_SDK to an iPhoneOS SDK with usr/lib/libSystem.tbd)"
fi

echo "built $ok, failed $fail"
find "$OUT" -maxdepth 1 -type f ! -name '*.pdb' -printf '%s %f\n' | sort

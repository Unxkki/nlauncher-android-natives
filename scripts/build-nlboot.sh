#!/usr/bin/env bash
# Builds nlboot/ (MIT JVM launcher, separate CMake project) with the same NDK settings
# and copies its outputs next to the LWJGL libraries:
#   libnlboot.so            -> $NL_BUILD_DIR/lib/libnlboot.so
#   nljava (executable)     -> $NL_BUILD_DIR/lib/libnljava.so
# (Android only extracts/executes files named lib*.so from an APK's native lib dir,
#  hence the rename of the executable.)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../versions.env
. "$ROOT/versions.env"

if [ ! -f "$ROOT/nlboot/CMakeLists.txt" ]; then
  echo "nlboot/CMakeLists.txt not found — nothing to build"
  exit 0
fi

TARGET_ABI="${TARGET_ABI:-arm64-v8a}"
NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-${ANDROID_NDK:-}}}"
[ -f "$NDK/build/cmake/android.toolchain.cmake" ] || { echo "error: ANDROID_NDK_HOME is not set" >&2; exit 1; }
BUILD="${NL_BUILD_DIR:-$ROOT/build/android-$TARGET_ABI}"
NLBOOT_BUILD="$BUILD-nlboot"
JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
GEN=()
command -v ninja >/dev/null 2>&1 && GEN=(-G Ninja)

cmake -S "$ROOT/nlboot" -B "$NLBOOT_BUILD" ${GEN[@]+"${GEN[@]}"} \
  -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI="$TARGET_ABI" \
  -DANDROID_PLATFORM="android-$ANDROID_API" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-z,max-page-size=16384" \
  -DCMAKE_EXE_LINKER_FLAGS="-Wl,-z,max-page-size=16384"
cmake --build "$NLBOOT_BUILD" --parallel "$JOBS"

lib="$(find "$NLBOOT_BUILD" -name libnlboot.so -type f | head -n 1)"
exe="$(find "$NLBOOT_BUILD" -name nljava -type f | head -n 1)"
[ -n "$lib" ] || { echo "error: libnlboot.so was not produced" >&2; exit 1; }
[ -n "$exe" ] || { echo "error: nljava was not produced" >&2; exit 1; }
mkdir -p "$BUILD/lib"
cp "$lib" "$BUILD/lib/libnlboot.so"
cp "$exe" "$BUILD/lib/libnljava.so"
echo "nlboot: $BUILD/lib/libnlboot.so, $BUILD/lib/libnljava.so"

#!/usr/bin/env bash
# Builds the Android natives with the NDK.
#
#   TARGET_ABI         arm64-v8a (default; the release target) or x86_64 (emulator)
#   ANDROID_NDK_HOME / ANDROID_NDK_ROOT / ANDROID_NDK
#                      NDK r28c (Pkg.Revision must match NDK_REVISION in versions.env;
#                      NL_ALLOW_OTHER_NDK=1 turns the mismatch into a warning)
#   NL_BUILD_DIR       build tree (default: build/android-$TARGET_ABI); libraries land in $NL_BUILD_DIR/lib
#   NL_BUILD_NLBOOT    1 (default) also builds nlboot/ when nlboot/CMakeLists.txt exists
#   NL_CMAKE_ARGS      extra arguments for the CMake configure step
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../versions.env
. "$ROOT/versions.env"

TARGET_ABI="${TARGET_ABI:-arm64-v8a}"
NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-${ANDROID_NDK:-}}}"
if [ -z "$NDK" ] || [ ! -f "$NDK/build/cmake/android.toolchain.cmake" ]; then
  echo "error: set ANDROID_NDK_HOME (or ANDROID_NDK_ROOT) to an NDK $NDK_VERSION ($NDK_REVISION)" >&2
  exit 1
fi
NDK_REV="$(sed -n 's/^Pkg.Revision *= *//p' "$NDK/source.properties" | tr -d '\r ')"
if [ "$NDK_REV" != "$NDK_REVISION" ]; then
  if [ "${NL_ALLOW_OTHER_NDK:-0}" = 1 ]; then
    echo "warning: NDK $NDK_REV != pinned $NDK_REVISION ($NDK_VERSION)" >&2
  else
    echo "error: NDK at $NDK is $NDK_REV, expected $NDK_REVISION ($NDK_VERSION). NL_ALLOW_OTHER_NDK=1 to override." >&2
    exit 1
  fi
fi

SOURCES="${NL_SOURCES_DIR:-$ROOT/sources}"
if [ ! -d "$SOURCES/$LWJGL_DIR" ]; then
  NL_SOURCES_DIR="$SOURCES" "$ROOT/scripts/fetch-sources.sh"
fi

BUILD="${NL_BUILD_DIR:-$ROOT/build/android-$TARGET_ABI}"
JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
GEN=()
command -v ninja >/dev/null 2>&1 && GEN=(-G Ninja)

# shellcheck disable=SC2086
cmake -S "$ROOT" -B "$BUILD" ${GEN[@]+"${GEN[@]}"} \
  -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI="$TARGET_ABI" \
  -DANDROID_PLATFORM="android-$ANDROID_API" \
  -DANDROID_STL=c++_static \
  -DCMAKE_BUILD_TYPE=Release \
  -DNL_SOURCES_DIR="$SOURCES" \
  ${NL_CMAKE_ARGS:-}
cmake --build "$BUILD" --parallel "$JOBS"

if [ "${NL_BUILD_NLBOOT:-1}" = 1 ] && [ -f "$ROOT/nlboot/CMakeLists.txt" ]; then
  NL_BUILD_DIR="$BUILD" TARGET_ABI="$TARGET_ABI" ANDROID_NDK_HOME="$NDK" "$ROOT/scripts/build-nlboot.sh"
fi

echo
echo "Built for $TARGET_ABI (API $ANDROID_API, NDK $NDK_REV):"
ls -l "$BUILD/lib"

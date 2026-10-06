#!/usr/bin/env bash
# Packages a finished build into the release artifact:
#
#   dist/lwjgl-<LWJGL_VERSION>-android-<arch>.tar.xz      (+ .sha256 next to it)
#   └── lwjgl-<LWJGL_VERSION>-android-<arch>/
#       ├── lib/*.so          flat: liblwjgl.so liblwjgl_opengl.so liblwjgl_stb.so liblwjgl_tinyfd.so
#       │                     libfreetype.so [libjemalloc.so] [libjnidispatch.so] [libnlboot.so libnljava.so]
#       ├── licenses/         every license text that applies to the binaries
#       └── BUILD-INFO.txt    versions, source sha256, patches, NDK, API, library sha256
#
#   TARGET_ABI    arm64-v8a (default) -> "arm64"; x86_64 -> "x64"
#   NL_BUILD_DIR  default: build/android-$TARGET_ABI
#   NL_DIST_DIR   default: dist
#   STRIP         strip tool (default: llvm-strip of the NDK used for the build)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../versions.env
. "$ROOT/versions.env"

TARGET_ABI="${TARGET_ABI:-arm64-v8a}"
case "$TARGET_ABI" in
  arm64-v8a) ARCH=arm64 ;;
  x86_64)    ARCH=x64 ;;
  *) echo "error: unsupported TARGET_ABI $TARGET_ABI" >&2; exit 1 ;;
esac
BUILD="${NL_BUILD_DIR:-$ROOT/build/android-$TARGET_ABI}"
DIST="${NL_DIST_DIR:-$ROOT/dist}"
SOURCES="${NL_SOURCES_DIR:-$ROOT/sources}"
NAME="lwjgl-$LWJGL_VERSION-android-$ARCH"
STAGE="$DIST/$NAME"

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}
cache_var() { sed -n "s/^$1:[A-Z]*=//p" "$BUILD/CMakeCache.txt" | head -n 1; }

test -f "$BUILD/CMakeCache.txt" || { echo "error: $BUILD is not a build directory" >&2; exit 1; }
NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-$(cache_var ANDROID_NDK)}}"
CC_PATH="$(cache_var CMAKE_C_COMPILER)"
if [ -z "$CC_PATH" ]; then   # compiler set by a toolchain file is not always cached
  CC_PATH="$(sed -n 's/^set(CMAKE_C_COMPILER "\(.*\)")$/\1/p' "$BUILD"/CMakeFiles/*/CMakeCCompiler.cmake 2>/dev/null | head -n 1)"
fi
if [ -z "${STRIP:-}" ]; then
  STRIP="$(ls "$NDK"/toolchains/llvm/prebuilt/*/bin/llvm-strip 2>/dev/null | head -n 1 || true)"
fi

REQUIRED="liblwjgl.so liblwjgl_opengl.so liblwjgl_stb.so liblwjgl_tinyfd.so libfreetype.so"
OPTIONAL="libjemalloc.so libjnidispatch.so libnlboot.so libnljava.so"

rm -rf "$STAGE" "$DIST/$NAME.tar.xz" "$DIST/$NAME.tar.xz.sha256"
mkdir -p "$STAGE/lib" "$STAGE/licenses"

for lib in $REQUIRED; do
  test -f "$BUILD/lib/$lib" || { echo "error: $BUILD/lib/$lib is missing" >&2; exit 1; }
  cp "$BUILD/lib/$lib" "$STAGE/lib/"
done
for lib in $OPTIONAL; do
  if [ -f "$BUILD/lib/$lib" ]; then cp "$BUILD/lib/$lib" "$STAGE/lib/"; else echo "note: $lib not built, skipped"; fi
done
if [ -n "$STRIP" ] && [ -x "$STRIP" ]; then
  for f in "$STAGE"/lib/*.so; do "$STRIP" --strip-unneeded "$f"; done
else
  echo "warning: llvm-strip not found, libraries are packaged unstripped" >&2
fi

# ---- licenses -----------------------------------------------------------------
L="$STAGE/licenses"
LW="$SOURCES/$LWJGL_DIR"
cp "$ROOT/LICENSE"                                         "$L/NLauncher-build-scripts-BSD-3-Clause.txt"
cp "$ROOT/THIRD-PARTY-NOTICES.md"                          "$L/THIRD-PARTY-NOTICES.md"
cp "$LW/LICENSE.md"                                        "$L/LWJGL-BSD-3-Clause.txt"
cp "$LW/modules/lwjgl/core/libffi_license.txt"             "$L/libffi-MIT.txt"
cp "$LW/modules/lwjgl/core/liburing_license.txt"           "$L/liburing-MIT.txt"
cp "$LW/modules/lwjgl/opengl/khronos_license.txt"          "$L/Khronos-OpenGL-registry.txt"
cp "$LW/modules/lwjgl/tinyfd/tinyfd_license.txt"           "$L/tinyfiledialogs-zlib.txt"
# stb has no separate license file: the dual MIT / public-domain text closes every header.
sed -n '/^This software is available under 2 licenses/,$p' \
  "$LW/modules/lwjgl/stb/src/main/c/stb_image.h" | sed '$d'  > "$L/stb-MIT-or-PublicDomain.txt"
cp "$SOURCES/$FREETYPE_DIR/docs/FTL.TXT"                   "$L/FreeType-FTL.txt"
cp "$SOURCES/$FREETYPE_DIR/LICENSE.TXT"                    "$L/FreeType-LICENSE.txt"
# FreeType's bundled zlib (src/gzip) keeps its own zlib license in zlib.h.
sed -n '/Copyright (C) 1995-/,/^\*\//p' "$SOURCES/$FREETYPE_DIR/src/gzip/zlib.h" > "$L/zlib-in-FreeType.txt"
if [ -f "$BUILD/lib/libfreetype.so" ] && grep -q "^NL_WITH_HARFBUZZ:BOOL=ON" "$BUILD/CMakeCache.txt"; then
  cp "$SOURCES/$HARFBUZZ_DIR/COPYING"                      "$L/HarfBuzz-MIT.txt"
fi
if [ -f "$STAGE/lib/libjemalloc.so" ]; then
  cp "$SOURCES/$JEMALLOC_DIR/COPYING"                      "$L/jemalloc-BSD-2-Clause.txt"
fi
if [ -f "$STAGE/lib/libjnidispatch.so" ]; then
  cp "$SOURCES/$JNA_DIR/AL2.0"                             "$L/JNA-Apache-2.0.txt"
  cp "$SOURCES/$JNA_DIR/LICENSE"                           "$L/JNA-LICENSE-choice.txt"
fi
if [ -f "$STAGE/lib/libnlboot.so" ]; then
  for f in "$ROOT/nlboot/LICENSE" "$ROOT/nlboot/LICENSE.txt" "$ROOT/nlboot/LICENSE.md"; do
    [ -f "$f" ] && cp "$f" "$L/nlboot-MIT.txt" && break
  done
  test -f "$L/nlboot-MIT.txt" || { echo "error: nlboot was built but nlboot/LICENSE is missing" >&2; exit 1; }
fi

# ---- BUILD-INFO.txt -----------------------------------------------------------
NDK_REV="$(sed -n 's/^Pkg.Revision *= *//p' "$NDK/source.properties" 2>/dev/null | tr -d '\r ' || true)"
CC_VER="$("$CC_PATH" --version 2>/dev/null | head -n 1 || true)"
GIT_REV="$(git -C "$ROOT" rev-parse --verify -q HEAD 2>/dev/null || echo unknown)"
GIT_DIRTY="$(git -C "$ROOT" status --porcelain 2>/dev/null | grep -q . && echo " (dirty)" || true)"
{
  echo "$NAME"
  echo "release tag:   lwjgl-$LWJGL_VERSION-nl$NL_BUILD_NUMBER"
  echo "built (UTC):   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "repository:    ${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-Unxkki/nlauncher-android-natives}"
  echo "commit:        $GIT_REV$GIT_DIRTY"
  [ -n "${GITHUB_RUN_ID:-}" ] && echo "CI run:        ${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
  echo
  echo "target:        Android $TARGET_ABI, minimum API $ANDROID_API, bionic, ELF LOAD segments aligned to 16 KiB"
  echo "NDK:           $NDK_VERSION (Pkg.Revision $NDK_REV; pinned $NDK_REVISION)"
  echo "compiler:      $CC_VER"
  echo "flags:         -O2, hidden visibility (only JNI / public C API exported), -Wl,-z,max-page-size=16384"
  echo
  echo "upstream sources (sha256 of the archives):"
  printf '  %-9s %-8s %s  %s\n' LWJGL    "$LWJGL_VERSION"    "$LWJGL_SHA256"    "$LWJGL_URL"
  printf '  %-9s %-8s %s  %s\n' libffi   "$LIBFFI_VERSION"   "$LIBFFI_SHA256"   "$LIBFFI_URL"
  printf '  %-9s %-8s %s  %s\n' FreeType "$FREETYPE_VERSION" "$FREETYPE_SHA256" "$FREETYPE_URL"
  printf '  %-9s %-8s %s  %s\n' HarfBuzz "$HARFBUZZ_VERSION" "$HARFBUZZ_SHA256" "$HARFBUZZ_URL"
  printf '  %-9s %-8s %s  %s\n' jemalloc "$JEMALLOC_VERSION" "$JEMALLOC_SHA256" "$JEMALLOC_URL"
  printf '  %-9s %-8s %s  %s\n' JNA      "$JNA_VERSION"      "$JNA_SHA256"      "$JNA_URL"
  echo
  echo "patches applied to upstream sources:"
  found=0
  for p in "$ROOT"/patches/*/*.patch; do
    [ -e "$p" ] || continue
    found=1
    echo "  $(sha256 "$p")  ${p#"$ROOT"/}"
  done
  [ "$found" = 1 ] || echo "  (none)"
  echo "additions (our code, BSD-3-Clause): src/jemalloc_free_sized.c (je_free_sized, je_free_aligned_sized)"
  echo
  echo "libraries (sha256, bytes):"
  for f in "$STAGE"/lib/*.so; do
    printf '  %s  %-22s %s\n' "$(sha256 "$f")" "$(basename "$f")" "$(wc -c < "$f" | tr -d ' ')"
  done
} > "$STAGE/BUILD-INFO.txt"

# ---- archive ------------------------------------------------------------------
if tar --version 2>/dev/null | grep -q 'GNU tar'; then
  tar -C "$DIST" --sort=name --owner=0 --group=0 --numeric-owner -cJf "$DIST/$NAME.tar.xz" "$NAME"
else
  tar -C "$DIST" -cJf "$DIST/$NAME.tar.xz" "$NAME"
fi
( cd "$DIST" && echo "$(sha256 "$NAME.tar.xz")  $NAME.tar.xz" > "$NAME.tar.xz.sha256" )
cat "$STAGE/BUILD-INFO.txt"
echo
echo "artifact: $DIST/$NAME.tar.xz"
cat "$DIST/$NAME.tar.xz.sha256"

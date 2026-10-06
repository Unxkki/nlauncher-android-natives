#!/usr/bin/env bash
# Downloads the pinned upstream sources listed in versions.env, verifies their
# sha256 and unpacks them into sources/ (git-ignored). Patches from
# patches/<component>/*.patch are applied afterwards (none for upstream code as of nl1).
#
#   NL_DOWNLOAD_DIR  where tarballs are cached   (default: .cache/downloads)
#   NL_SOURCES_DIR   where sources are unpacked  (default: sources)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../versions.env
. "$ROOT/versions.env"

DL="${NL_DOWNLOAD_DIR:-$ROOT/.cache/downloads}"
SRC="${NL_SOURCES_DIR:-$ROOT/sources}"
mkdir -p "$DL" "$SRC"

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# fetch <file name> <sha256> <url> [fallback url...]
fetch() {
  local name="$1" want="$2"; shift 2
  local out="$DL/$name"
  if [ -f "$out" ] && [ "$(sha256 "$out")" = "$want" ]; then
    echo "cached   $name"; return 0
  fi
  local url
  for url in "$@"; do
    echo "download $name <- $url"
    if curl -fsSL --retry 3 --retry-delay 5 --connect-timeout 30 -o "$out.part" "$url"; then
      local got; got="$(sha256 "$out.part")"
      if [ "$got" = "$want" ]; then mv "$out.part" "$out"; return 0; fi
      echo "sha256 mismatch for $name: got $got, want $want" >&2
    fi
    rm -f "$out.part"
  done
  echo "error: could not fetch $name" >&2
  exit 1
}

# unpack <archive> <top-level dir> [tar member patterns...]
unpack() {
  local name="$1" dir="$2"; shift 2
  local archive="$DL/$name"
  rm -rf "${SRC:?}/$dir"
  echo "unpack   $name -> sources/$dir"
  # Partial extraction needs GNU tar (--wildcards); bsdtar (macOS) unpacks everything.
  if [ $# -gt 0 ] && tar --version 2>/dev/null | grep -q 'GNU tar'; then
    tar -xf "$archive" -C "$SRC" --wildcards "$@"
  else
    tar -xf "$archive" -C "$SRC"
  fi
  test -d "$SRC/$dir" || { echo "error: $name did not contain $dir/" >&2; exit 1; }
}

apply_patches() {
  local comp="$1" dir="$2" p
  for p in "$ROOT/patches/$comp"/*.patch; do
    [ -e "$p" ] || continue
    echo "patch    $dir < patches/$comp/$(basename "$p")"
    patch -d "$SRC/$dir" -p1 --forward --batch < "$p"
  done
}

fetch "lwjgl3-$LWJGL_VERSION.tar.gz"       "$LWJGL_SHA256"    "$LWJGL_URL"
fetch "libffi-$LIBFFI_VERSION.tar.gz"      "$LIBFFI_SHA256"   "$LIBFFI_URL"
fetch "freetype-$FREETYPE_VERSION.tar.xz"  "$FREETYPE_SHA256" "$FREETYPE_URL" "$FREETYPE_URL_FALLBACK"
fetch "harfbuzz-$HARFBUZZ_VERSION.tar.xz"  "$HARFBUZZ_SHA256" "$HARFBUZZ_URL"
fetch "jemalloc-$JEMALLOC_VERSION.tar.bz2" "$JEMALLOC_SHA256" "$JEMALLOC_URL"
fetch "jna-$JNA_VERSION.tar.gz"            "$JNA_SHA256"      "$JNA_URL"

# LWJGL: only what the native build needs (C sources, build config, licenses).
unpack "lwjgl3-$LWJGL_VERSION.tar.gz" "$LWJGL_DIR" \
  "$LWJGL_DIR/LICENSE.md" "$LWJGL_DIR/config/*" \
  "$LWJGL_DIR/modules/lwjgl/core/*" "$LWJGL_DIR/modules/lwjgl/jawt/*" \
  "$LWJGL_DIR/modules/lwjgl/opengl/*" "$LWJGL_DIR/modules/lwjgl/stb/*" \
  "$LWJGL_DIR/modules/lwjgl/tinyfd/*" "$LWJGL_DIR/modules/lwjgl/freetype/*" \
  "$LWJGL_DIR/modules/lwjgl/jemalloc/*"
unpack "libffi-$LIBFFI_VERSION.tar.gz" "$LIBFFI_DIR"
unpack "freetype-$FREETYPE_VERSION.tar.xz" "$FREETYPE_DIR"
# HarfBuzz release tarballs carry a large test corpus; only src/ is compiled.
unpack "harfbuzz-$HARFBUZZ_VERSION.tar.xz" "$HARFBUZZ_DIR" \
  "$HARFBUZZ_DIR/src/*" "$HARFBUZZ_DIR/COPYING"
unpack "jemalloc-$JEMALLOC_VERSION.tar.bz2" "$JEMALLOC_DIR"
# The JNA git archive also contains prebuilt jars for every platform; we only
# need the native sources, the Java sources (for javac -h) and the licenses.
unpack "jna-$JNA_VERSION.tar.gz" "$JNA_DIR" \
  "$JNA_DIR/native/*" "$JNA_DIR/src/com/sun/jna/*" \
  "$JNA_DIR/LICENSE" "$JNA_DIR/AL2.0" "$JNA_DIR/LGPL2.1"

apply_patches lwjgl    "$LWJGL_DIR"
apply_patches libffi   "$LIBFFI_DIR"
apply_patches freetype "$FREETYPE_DIR"
apply_patches harfbuzz "$HARFBUZZ_DIR"
apply_patches jemalloc "$JEMALLOC_DIR"
apply_patches jna      "$JNA_DIR"

{
  echo "# sha256 of the upstream archives unpacked into this directory"
  for f in "lwjgl3-$LWJGL_VERSION.tar.gz" "libffi-$LIBFFI_VERSION.tar.gz" \
           "freetype-$FREETYPE_VERSION.tar.xz" "harfbuzz-$HARFBUZZ_VERSION.tar.xz" \
           "jemalloc-$JEMALLOC_VERSION.tar.bz2" "jna-$JNA_VERSION.tar.gz"; do
    echo "$(sha256 "$DL/$f")  $f"
  done
} > "$SRC/SOURCES.sha256"
echo "sources ready in $SRC"

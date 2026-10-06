#!/usr/bin/env bash
# Host smoke test: loads the -DNL_HOST=ON build into a desktop JVM with the stock
# LWJGL 3.3.3 / JNA 5.14.0 jars (Java classes only — no natives jars, no extraction).
#
#   tests/host/run.sh [<build dir>]      default build dir: build/host
#
#   NL_JARS_DIR   where the jars are cached (default: tests/host/.jars)
#   JAVA_HOME     JDK 11+ (the single-file source launcher is used)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../../versions.env
. "$ROOT/versions.env"
BUILD="$(cd "${1:-$ROOT/build/host}" && pwd)"
LIB="$BUILD/lib"
JARS="${NL_JARS_DIR:-$ROOT/tests/host/.jars}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/nl-natives-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

JAVA="${JAVA_HOME:+$JAVA_HOME/bin/}java"
test -f "$LIB/liblwjgl.so" || { echo "error: $LIB/liblwjgl.so not found (build with -DNL_HOST=ON first)" >&2; exit 1; }

# Maven Central coordinates and sha256 of the plain (non-natives) jars.
MAVEN=https://repo1.maven.org/maven2
JAR_LIST="
org/lwjgl/lwjgl/$LWJGL_VERSION/lwjgl-$LWJGL_VERSION.jar dc9c7b2d48e8396d68895f8902ffa01e46253de44dfe927533ff09457ebfeec4
org/lwjgl/lwjgl-opengl/$LWJGL_VERSION/lwjgl-opengl-$LWJGL_VERSION.jar 5062da750e5f7ec89e27e8b67b7d40fa8c4b16890159e35f828116ce6c8eca1e
org/lwjgl/lwjgl-stb/$LWJGL_VERSION/lwjgl-stb-$LWJGL_VERSION.jar 0cff7aa46ea9d70fcc20857015293ea80fbf21adcac34600c84da9b81a44ca93
org/lwjgl/lwjgl-tinyfd/$LWJGL_VERSION/lwjgl-tinyfd-$LWJGL_VERSION.jar ee0515054ee19a3f4088426fee9d879eb2ee657b07e5064e4e2c851f6adcf14b
org/lwjgl/lwjgl-freetype/$LWJGL_VERSION/lwjgl-freetype-$LWJGL_VERSION.jar e1a7ab07106349d9a8a68f6860b7b73b353c502b81e662aca77f931c6fdd3de8
org/lwjgl/lwjgl-harfbuzz/$LWJGL_VERSION/lwjgl-harfbuzz-$LWJGL_VERSION.jar 29a6e77c9441d5a7f646015838e89b2c125bed3f986b98649095078767c2ffb2
org/lwjgl/lwjgl-jemalloc/$LWJGL_VERSION/lwjgl-jemalloc-$LWJGL_VERSION.jar e99e31269e6678a4bfc62ef24c50a481c01cbdd004861ece9a59ba12768c6516
net/java/dev/jna/jna/$JNA_VERSION/jna-$JNA_VERSION.jar 34ed1e1f27fa896bca50dbc4e99cf3732967cec387a7a0d5e3486c09673fe8c6
"
mkdir -p "$JARS"
CP=""
while read -r path sum; do
  [ -n "$path" ] || continue
  jar="$JARS/$(basename "$path")"
  if [ ! -f "$jar" ] || [ "$(sha256sum "$jar" | cut -d' ' -f1)" != "$sum" ]; then
    curl -fsSL --retry 3 -o "$jar.part" "$MAVEN/$path"
    [ "$(sha256sum "$jar.part" | cut -d' ' -f1)" = "$sum" ] || { echo "sha256 mismatch: $path" >&2; exit 1; }
    mv "$jar.part" "$jar"
  fi
  CP="$CP${CP:+:}$jar"
done <<< "$JAR_LIST"

ALLOCATOR=system
[ -f "$LIB/libjemalloc.so" ] && ALLOCATOR=jemalloc

mkdir -p "$WORK/extract"
echo "note: with -Dorg.lwjgl.util.Debug=true LWJGL compares each library with the sha1 of the"
echo "      official build and prints '[LWJGL] [ERROR] Incompatible Java and native library"
echo "      versions' for every library it loads. That is expected for a different build;"
echo "      the test itself checks the JNI exports and which files were actually mapped."
set +e
"$JAVA" \
  -cp "$CP" \
  -Dorg.lwjgl.librarypath="$LIB" \
  -Dorg.lwjgl.system.SharedLibraryExtractPath="$WORK/extract" \
  -Dorg.lwjgl.system.allocator="$ALLOCATOR" \
  -Dorg.lwjgl.util.Debug=true \
  -Dorg.lwjgl.util.DebugLoader=true \
  -Djna.boot.library.path="$LIB" \
  -Djna.nosys=true -Djna.noclasspath=true -Djna.nounpack=true \
  -Djava.io.tmpdir="$WORK" \
  "$ROOT/tests/host/NativesSmokeTest.java"
rc=$?
set -e
if [ -n "$(ls -A "$WORK/extract")" ]; then
  echo "FAIL: LWJGL extracted natives into $WORK/extract:" >&2; ls -la "$WORK/extract" >&2; exit 1
fi
exit $rc

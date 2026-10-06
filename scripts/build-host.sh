#!/usr/bin/env bash
# Host build (linux, no NDK) of the same modules, for tests/host/run.sh.
#   NL_BUILD_DIR   default: build/host      CC/CXX   host compilers (gcc or clang)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../versions.env
. "$ROOT/versions.env"

SOURCES="${NL_SOURCES_DIR:-$ROOT/sources}"
if [ ! -d "$SOURCES/$LWJGL_DIR" ]; then
  NL_SOURCES_DIR="$SOURCES" "$ROOT/scripts/fetch-sources.sh"
fi
BUILD="${NL_BUILD_DIR:-$ROOT/build/host}"
JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"

# shellcheck disable=SC2086
cmake -S "$ROOT" -B "$BUILD" -DNL_HOST=ON -DCMAKE_BUILD_TYPE=Release \
  -DNL_SOURCES_DIR="$SOURCES" ${NL_CMAKE_ARGS:-}
cmake --build "$BUILD" --parallel "$JOBS"
ls -l "$BUILD/lib"

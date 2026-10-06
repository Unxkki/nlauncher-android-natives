# Native libraries of upstream LWJGL 3.3.3 (+ FreeType/HarfBuzz, jemalloc, JNA jnidispatch)
# for Android, built with the NDK. See README.md.
#
# Android (the real target):
#   cmake -S . -B build/android-arm64 \
#     -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
#     -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=29 -DCMAKE_BUILD_TYPE=Release
#
# Host check (linux x86_64, no NDK needed): builds the very same module source lists
# with the host compiler so that tests/host can load them into a desktop JVM.
#   cmake -S . -B build/host -DNL_HOST=ON -DCMAKE_BUILD_TYPE=Release
cmake_minimum_required(VERSION 3.22)

project(nlauncher_android_natives LANGUAGES C CXX ASM)

option(NL_HOST          "Build for the host (linux) instead of Android, for tests/host" OFF)
option(NL_WITH_FREETYPE "Build libfreetype.so (lwjgl-freetype)"                         ON)
option(NL_WITH_HARFBUZZ "Link HarfBuzz into libfreetype.so, like LWJGL's own build"      ON)
option(NL_WITH_JEMALLOC "Build libjemalloc.so (lwjgl-jemalloc)"                          ON)
option(NL_WITH_JNA      "Build libjnidispatch.so (JNA)"                                  ON)
option(NL_LWJGL_JAWT    "Include JAWT JNI functions in liblwjgl.so (needs jawt_md.h + X11 headers; no AWT on Android)" OFF)
option(NL_LIBFFI_STATIC_TRAMP "Keep libffi's default static trampolines"                ON)

set(NL_SOURCES_DIR "${CMAKE_CURRENT_SOURCE_DIR}/sources" CACHE PATH
    "Directory with the unpacked upstream sources (scripts/fetch-sources.sh)")

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

include(NLVersions)   # reads versions.env
include(NLPlatform)   # target detection, common flags, nl_shared_library()
include(NLLibffi)     # libffi (configure, static, PIC)
include(NLLwjgl)      # liblwjgl.so, liblwjgl_opengl.so, liblwjgl_stb.so, liblwjgl_tinyfd.so
if(NL_WITH_FREETYPE)
  include(NLFreetype) # libfreetype.so (+ HarfBuzz)
endif()
if(NL_WITH_JEMALLOC)
  include(NLJemalloc) # libjemalloc.so
endif()
if(NL_WITH_JNA)
  include(NLJna)      # libjnidispatch.so
endif()

# Everything ends up flat in <build>/lib, which is what scripts/package.sh and tests/host consume.
message(STATUS "NL: target=${NL_TARGET_DESC} output=${NL_OUTPUT_DIR}")

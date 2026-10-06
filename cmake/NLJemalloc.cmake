# libjemalloc.so for lwjgl-jemalloc (org.lwjgl.system.jemalloc.JEmalloc).
#
# Configure flags follow LWJGL-CI/jemalloc (.github/workflows/lwjgl.yml):
#   --with-jemalloc-prefix=je_ --disable-stats --disable-fill --disable-cxx
#   --enable-doc=no --disable-initial-exec-tls, and --with-lg-page=16 on arm64.
# --disable-initial-exec-tls matters on Android too: bionic refuses to dlopen()
# libraries that use the initial-exec TLS model. lg-page=16 (64 KiB) is correct
# on 4 KiB and 16 KiB page devices alike.
#
# LWJGL 3.3.3 is built against a jemalloc dev snapshot and resolves je_free_sized
# and je_free_aligned_sized, which the 5.3.0 release does not have. Without them
# JEmalloc's static initializer fails and LWJGL silently falls back to the system
# allocator, so src/jemalloc_free_sized.c adds both on top of je_sdallocx.

set(NL_JEMALLOC_BUILD "${CMAKE_BINARY_DIR}/jemalloc-build")
set(NL_JEMALLOC_PIC "${NL_JEMALLOC_BUILD}/lib/libjemalloc_pic.a")

set(_nl_je_args
  --with-jemalloc-prefix=je_
  --disable-stats --disable-fill --disable-cxx --enable-doc=no
  --disable-initial-exec-tls
  --disable-libdl)
if(NL_LWJGL_ARCH STREQUAL "arm64")
  list(APPEND _nl_je_args --with-lg-page=16)
elseif(NOT NL_HOST)
  list(APPEND _nl_je_args --with-lg-page=12)   # x86_64 emulator; configure cannot probe when cross-compiling
endif()

ExternalProject_Add(nl_jemalloc_build
  SOURCE_DIR "${NL_JEMALLOC_DIR}"
  BINARY_DIR "${NL_JEMALLOC_BUILD}"
  CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${NL_AUTOTOOLS_ENV}
                    "EXTRA_CFLAGS=-ffunction-sections -fdata-sections"
                    <SOURCE_DIR>/configure ${NL_AUTOTOOLS_HOST_ARG} ${_nl_je_args}
  BUILD_COMMAND ${NL_MAKE} -j${NL_NPROC} build_lib_static
  INSTALL_COMMAND ""
  BUILD_BYPRODUCTS "${NL_JEMALLOC_PIC}"
  LOG_CONFIGURE ON LOG_BUILD ON LOG_OUTPUT_ON_FAILURE ON)

nl_shared_library(jemalloc OUTPUT_NAME jemalloc
  VERSION_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/cmake/jemalloc.version.script")
target_sources(jemalloc PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src/jemalloc_free_sized.c")
target_include_directories(jemalloc PRIVATE "${NL_JEMALLOC_BUILD}/include")
add_dependencies(jemalloc nl_jemalloc_build)
# Whole archive: every public je_* entry point must end up in the .so.
target_link_libraries(jemalloc PRIVATE
  -Wl,--whole-archive "${NL_JEMALLOC_PIC}" -Wl,--no-whole-archive m)
if(NL_HOST)
  target_link_libraries(jemalloc PRIVATE ${CMAKE_DL_LIBS})
endif()

# libffi, built from the upstream release with its own configure script, exactly
# like LWJGL-CI/libffi does for Linux (./configure --disable-shared --with-pic),
# then linked statically into liblwjgl.so and libjnidispatch.so.

set(NL_LIBFFI_PREFIX "${CMAKE_BINARY_DIR}/libffi")
set(NL_LIBFFI_LIBRARY "${NL_LIBFFI_PREFIX}/lib/libffi.a")
set(NL_LIBFFI_INCLUDE_DIR "${NL_LIBFFI_PREFIX}/include")
file(MAKE_DIRECTORY "${NL_LIBFFI_INCLUDE_DIR}")

set(_nl_ffi_args
  --disable-shared --enable-static --with-pic
  --disable-docs --disable-multi-os-directory
  "--prefix=${NL_LIBFFI_PREFIX}")
if(NOT NL_LIBFFI_STATIC_TRAMP)
  list(APPEND _nl_ffi_args --disable-exec-static-tramp)
endif()

# libffi 3.4.4's src/tramp.c calls open_temp_exec_file() (defined in closures.c)
# without a prototype; clang >= 16 (NDK r26+) rejects that by default. The function
# returns int, so the implicit declaration is ABI-correct: downgrade it to a warning
# instead of patching upstream code (libffi fixed it after 3.4.4).
set(_nl_ffi_env ${NL_AUTOTOOLS_ENV})
list(TRANSFORM _nl_ffi_env REPLACE "^CFLAGS=(.*)$" "CFLAGS=\\1 -Wno-error=implicit-function-declaration")

ExternalProject_Add(nl_libffi_build
  SOURCE_DIR "${NL_LIBFFI_DIR}"
  BINARY_DIR "${CMAKE_BINARY_DIR}/libffi-build"
  INSTALL_DIR "${NL_LIBFFI_PREFIX}"
  CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${_nl_ffi_env}
                    <SOURCE_DIR>/configure ${NL_AUTOTOOLS_HOST_ARG} ${_nl_ffi_args}
  BUILD_COMMAND ${NL_MAKE} -j${NL_NPROC}
  INSTALL_COMMAND ${NL_MAKE} install
  BUILD_BYPRODUCTS "${NL_LIBFFI_LIBRARY}"
  LOG_CONFIGURE ON LOG_BUILD ON LOG_INSTALL ON LOG_OUTPUT_ON_FAILURE ON)

add_library(nl_libffi STATIC IMPORTED GLOBAL)
set_target_properties(nl_libffi PROPERTIES IMPORTED_LOCATION "${NL_LIBFFI_LIBRARY}")
add_dependencies(nl_libffi nl_libffi_build)

# LWJGL 3.3.3 JNI libraries. The source lists mirror the Linux build of upstream
# LWJGL (config/linux/build.xml, targets "core", "opengl", "stb", "tinyfd"), with
# the same defines and the same exported-symbol version script.

set(_lw "${NL_LWJGL_DIR}/modules/lwjgl")
set(NL_LWJGL_VERSION_SCRIPT "${NL_LWJGL_DIR}/config/linux/version.script")

# nl_lwjgl_module(<target> <output name> <sources...>)
function(nl_lwjgl_module target name)
  nl_shared_library(${target} OUTPUT_NAME ${name} VERSION_SCRIPT "${NL_LWJGL_VERSION_SCRIPT}")
  target_sources(${target} PRIVATE ${ARGN})
  target_compile_definitions(${target} PRIVATE
    NDEBUG LWJGL_LINUX LWJGL_${NL_LWJGL_ARCH} _GNU_SOURCE _FILE_OFFSET_BITS=64)
  if(NL_HOST)
    # Same as upstream: avoid __*_chk symbols that pin a newer glibc.
    target_compile_options(${target} PRIVATE -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0)
  endif()
  target_include_directories(${target} PRIVATE
    "${_lw}/core/src/main/c"
    "${_lw}/core/src/main/c/linux")
endfunction()

# ---- liblwjgl.so: core + libffi ---------------------------------------------
set(_core "${_lw}/core/src")
file(GLOB _core_srcs CONFIGURE_DEPENDS
  "${_core}/main/c/*.c"
  "${_core}/generated/c/*.c"
  "${_core}/generated/c/linux/*.c")
file(GLOB _uring_srcs CONFIGURE_DEPENDS "${_core}/main/c/linux/liburing/*.c")
if(NL_LWJGL_JAWT)
  file(GLOB _jawt_srcs CONFIGURE_DEPENDS "${_lw}/jawt/src/generated/c/*.c")
endif()
nl_lwjgl_module(lwjgl lwjgl ${_core_srcs} ${_uring_srcs} ${_jawt_srcs})
set_source_files_properties(${_uring_srcs} PROPERTIES COMPILE_DEFINITIONS CONFIG_HAVE_MEMFD_CREATE)

if(NL_LWJGL_ARCH STREQUAL "arm64")
  set(_ffi_arch aarch64)
else()
  set(_ffi_arch x86)
  target_compile_definitions(lwjgl PRIVATE X86_64)   # for libffi/x86/ffitarget.h
endif()
# Upstream compiles core against LWJGL's own copy of ffi.h (libffi 3.4.x) and links libffi.a.
target_include_directories(lwjgl PRIVATE
  "${_core}/main/c/libffi"
  "${_core}/main/c/libffi/${_ffi_arch}"
  "${_core}/main/c/linux/liburing"
  "${_core}/main/c/linux/liburing/include")
target_link_libraries(lwjgl PRIVATE nl_libffi ${CMAKE_DL_LIBS})

# ---- liblwjgl_opengl.so -----------------------------------------------------
file(GLOB _gl_srcs CONFIGURE_DEPENDS "${_lw}/opengl/src/generated/c/*.c")
list(FILTER _gl_srcs EXCLUDE REGEX "org_lwjgl_opengl_WGL\\.c$")
nl_lwjgl_module(lwjgl_opengl lwjgl_opengl ${_gl_srcs})
target_include_directories(lwjgl_opengl PRIVATE "${_lw}/opengl/src/main/c")

# ---- liblwjgl_stb.so --------------------------------------------------------
file(GLOB _stb_srcs CONFIGURE_DEPENDS "${_lw}/stb/src/generated/c/*.c")
nl_lwjgl_module(lwjgl_stb lwjgl_stb ${_stb_srcs})
target_include_directories(lwjgl_stb SYSTEM PRIVATE "${_lw}/stb/src/main/c")
target_link_libraries(lwjgl_stb PRIVATE m)

# ---- liblwjgl_tinyfd.so -----------------------------------------------------
# tinyfiledialogs looks for zenity/kdialog/xdialog/... at run time. None exist on
# Android, so every dialog call simply reports failure (0/NULL); nothing to patch.
file(GLOB _tinyfd_srcs CONFIGURE_DEPENDS
  "${_lw}/tinyfd/src/main/c/*.c"
  "${_lw}/tinyfd/src/generated/c/*.c")
nl_lwjgl_module(lwjgl_tinyfd lwjgl_tinyfd ${_tinyfd_srcs})
target_include_directories(lwjgl_tinyfd PRIVATE "${_lw}/tinyfd/src/main/c")

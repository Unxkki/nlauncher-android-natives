# libfreetype.so for lwjgl-freetype.
#
# LWJGL 3.3.3 has no liblwjgl_freetype.so: org.lwjgl.util.freetype.FreeType loads a
# plain FreeType shared library named libfreetype.so (Configuration.FREETYPE_LIBRARY_NAME)
# and resolves every FT_* function with dlsym. LWJGL-CI builds it with meson as
# FreeType + HarfBuzz (whole archive, HarfBuzz API exported), error strings on,
# brotli/bzip2 off. We mirror that with plain CMake; PNG (colour bitmap glyphs) is
# left out, zlib comes from FreeType's own bundled copy (src/gzip).

set(_ft "${NL_FREETYPE_DIR}")
set(_hb "${NL_HARFBUZZ_DIR}")

set(_ft_srcs
  src/autofit/autofit.c
  src/base/ftbase.c
  src/base/ftbbox.c
  src/base/ftbdf.c
  src/base/ftbitmap.c
  src/base/ftcid.c
  src/base/ftfstype.c
  src/base/ftgasp.c
  src/base/ftglyph.c
  src/base/ftgxval.c
  src/base/ftinit.c
  src/base/ftmm.c
  src/base/ftotval.c
  src/base/ftpatent.c
  src/base/ftpfr.c
  src/base/ftstroke.c
  src/base/ftsynth.c
  src/base/fttype1.c
  src/base/ftwinfnt.c
  src/base/ftdebug.c
  builds/unix/ftsystem.c          # mmap-based file access, as in the meson build on Linux
  src/bdf/bdf.c
  src/bzip2/ftbzip2.c
  src/cache/ftcache.c
  src/cff/cff.c
  src/cid/type1cid.c
  src/gzip/ftgzip.c
  src/lzw/ftlzw.c
  src/pcf/pcf.c
  src/pfr/pfr.c
  src/psaux/psaux.c
  src/pshinter/pshinter.c
  src/psnames/psnames.c
  src/raster/raster.c
  src/sdf/sdf.c
  src/sfnt/sfnt.c
  src/smooth/smooth.c
  src/svg/svg.c
  src/truetype/truetype.c
  src/type1/type1.c
  src/type42/type42.c
  src/winfonts/winfnt.c)
list(TRANSFORM _ft_srcs PREPEND "${_ft}/")

nl_shared_library(freetype OUTPUT_NAME freetype)
target_sources(freetype PRIVATE ${_ft_srcs})
target_include_directories(freetype PRIVATE "${_ft}/include")
target_compile_definitions(freetype PRIVATE
  NDEBUG
  FT2_BUILD_LIBRARY=1
  FT_CONFIG_OPTION_ERROR_STRINGS   # meson -Derror_strings=true
  HAVE_UNISTD_H=1
  HAVE_FCNTL_H=1)
# FT_EXPORT() functions carry visibility("default"); everything else stays hidden.

if(NL_WITH_HARFBUZZ)
  target_sources(freetype PRIVATE "${_hb}/src/harfbuzz.cc")
  target_include_directories(freetype PRIVATE "${_hb}/src")
  target_compile_definitions(freetype PRIVATE FT_CONFIG_OPTION_USE_HARFBUZZ)
  # HarfBuzz configuration equivalent to its meson build with freetype=enabled,
  # experimental_api=true (LWJGL-CI), on a Linux/bionic libc.
  set_source_files_properties("${_hb}/src/harfbuzz.cc" PROPERTIES
    COMPILE_DEFINITIONS "HAVE_FREETYPE=1;HAVE_FT_GET_VAR_BLEND_COORDINATES=1;HAVE_FT_SET_VAR_BLEND_COORDINATES=1;HAVE_FT_DONE_MM_VAR=1;HAVE_FT_GET_TRANSFORM=1;HAVE_PTHREAD=1;HAVE_UNISTD_H=1;HAVE_SYS_MMAN_H=1;HAVE_STDBOOL_H=1;HAVE_ATEXIT=1;HAVE_MPROTECT=1;HAVE_SYSCONF=1;HAVE_GETPAGESIZE=1;HAVE_MMAP=1;HAVE_ISATTY=1;HAVE_USELOCALE=1;HAVE_NEWLOCALE=1;HAVE_SINCOSF=1;HB_EXPERIMENTAL_API=1;HB_EXTERN=__attribute__((visibility(\"default\"))) extern"
    COMPILE_OPTIONS "-fno-exceptions;-fno-rtti;-fno-threadsafe-statics")
  set_target_properties(freetype PROPERTIES CXX_STANDARD 11 CXX_EXTENSIONS OFF)
  if(NL_HOST)
    # Keep the host test library self-contained (HarfBuzz needs no C++ runtime symbols,
    # this only guards against libstdc++ being pulled in by the linker driver).
    target_link_options(freetype PRIVATE -static-libstdc++ -static-libgcc)
  else()
    # NDK default STL is c++_static; never re-export anything from it.
    target_link_options(freetype PRIVATE -Wl,--exclude-libs,ALL)
  endif()
endif()
target_link_libraries(freetype PRIVATE m)

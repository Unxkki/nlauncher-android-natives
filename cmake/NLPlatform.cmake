# Target detection and the flags shared by every library we build.

include(ExternalProject)

if(NL_HOST)
  if(NOT CMAKE_SYSTEM_NAME STREQUAL "Linux")
    message(FATAL_ERROR "NL_HOST=ON is only supported on Linux hosts")
  endif()
  if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|AMD64|amd64)$")
    set(NL_LWJGL_ARCH x64)
  elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64)$")
    set(NL_LWJGL_ARCH arm64)
  else()
    message(FATAL_ERROR "Unsupported host CPU ${CMAKE_SYSTEM_PROCESSOR}")
  endif()
  set(NL_GNU_HOST "")                     # native configure
  set(NL_TARGET_DESC "host-linux-${NL_LWJGL_ARCH}")

  # JNI headers of the host JDK (Android gets jni.h from the NDK sysroot).
  set(NL_JAVA_HOME "$ENV{JAVA_HOME}" CACHE PATH "JDK used for JNI headers (and javac -h for JNA)")
  if(NOT NL_JAVA_HOME OR NOT EXISTS "${NL_JAVA_HOME}/include/jni.h")
    find_program(_nl_javac javac REQUIRED)
    get_filename_component(_nl_javac "${_nl_javac}" REALPATH)
    get_filename_component(NL_JAVA_HOME "${_nl_javac}/../.." ABSOLUTE)
  endif()
  if(NOT EXISTS "${NL_JAVA_HOME}/include/jni.h")
    message(FATAL_ERROR "jni.h not found under ${NL_JAVA_HOME}; set JAVA_HOME")
  endif()
  set(NL_JNI_INCLUDES "${NL_JAVA_HOME}/include" "${NL_JAVA_HOME}/include/linux")
  find_package(Threads REQUIRED)
else()
  if(NOT ANDROID)
    message(FATAL_ERROR "Configure with the NDK toolchain "
      "(-DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake) or with -DNL_HOST=ON")
  endif()
  if(ANDROID_ABI STREQUAL "arm64-v8a")
    set(NL_LWJGL_ARCH arm64)
    set(NL_GNU_HOST aarch64-linux-android)
  elseif(ANDROID_ABI STREQUAL "x86_64")      # emulator builds; not part of the release
    set(NL_LWJGL_ARCH x64)
    set(NL_GNU_HOST x86_64-linux-android)
  else()
    message(FATAL_ERROR "Unsupported ANDROID_ABI ${ANDROID_ABI} (arm64-v8a or x86_64)")
  endif()
  if(NOT ANDROID_PLATFORM_LEVEL)
    message(FATAL_ERROR "ANDROID_PLATFORM_LEVEL is not set by the toolchain")
  endif()
  set(NL_TARGET_DESC "android-${ANDROID_ABI}-api${ANDROID_PLATFORM_LEVEL}")
  set(NL_JNI_INCLUDES "")
endif()

set(NL_OUTPUT_DIR "${CMAKE_BINARY_DIR}/lib")
file(MAKE_DIRECTORY "${NL_OUTPUT_DIR}")

# 16 KB page alignment is mandatory for Android 15+ devices with 16 KB pages
# (NDK r28 defaults to it already; we state it explicitly for every library).
set(NL_COMMON_LINK_OPTIONS
  -Wl,-z,max-page-size=16384
  -Wl,-z,noexecstack
  -Wl,--no-undefined
  -Wl,--gc-sections)
set(NL_COMMON_COMPILE_OPTIONS -O2 -ffunction-sections -fdata-sections)

# nl_shared_library(<target> [VERSION_SCRIPT <file>] [OUTPUT_NAME <name>])
#   Shared library with hidden visibility (only JNIEXPORT/explicitly exported symbols
#   stay visible), PIC, -O2, 16 KB pages, written to ${NL_OUTPUT_DIR}.
function(nl_shared_library target)
  cmake_parse_arguments(ARG "" "VERSION_SCRIPT;OUTPUT_NAME" "" ${ARGN})
  add_library(${target} SHARED)
  set_target_properties(${target} PROPERTIES
    C_STANDARD 11
    C_EXTENSIONS ON
    C_VISIBILITY_PRESET hidden
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN ON
    POSITION_INDEPENDENT_CODE ON
    LIBRARY_OUTPUT_DIRECTORY "${NL_OUTPUT_DIR}")
  if(ARG_OUTPUT_NAME)
    set_target_properties(${target} PROPERTIES OUTPUT_NAME "${ARG_OUTPUT_NAME}")
  endif()
  target_compile_options(${target} PRIVATE ${NL_COMMON_COMPILE_OPTIONS})
  target_link_options(${target} PRIVATE ${NL_COMMON_LINK_OPTIONS})
  if(ARG_VERSION_SCRIPT)
    target_link_options(${target} PRIVATE "-Wl,--version-script,${ARG_VERSION_SCRIPT}")
    set_property(TARGET ${target} APPEND PROPERTY LINK_DEPENDS "${ARG_VERSION_SCRIPT}")
  endif()
  if(NL_HOST)
    target_include_directories(${target} SYSTEM PRIVATE ${NL_JNI_INCLUDES})
    target_link_libraries(${target} PRIVATE Threads::Threads)
  endif()
endfunction()

# ---- Settings for the autotools sub-builds (libffi, jemalloc) -------------------
# They are configured with the same compiler CMake uses; for Android the target
# triple (with API level) and the NDK sysroot are passed explicitly, the same thing
# the NDK's <triple><api>-clang wrapper scripts do.
set(NL_AUTOTOOLS_CC "${CMAKE_C_COMPILER}")
# CMAKE_C_FLAGS / CMAKE_EXE_LINKER_FLAGS carry the toolchain's defaults (for the NDK:
# -DANDROID, -fstack-protector-strong, -D_FORTIFY_SOURCE=2, linker selection, ...).
# -Wno-error=format-security: the NDK adds -Werror=format-security, which upstream
# autotools code was never built with; keep it a warning there.
string(STRIP "${CMAKE_C_FLAGS} -O2 -fPIC -fvisibility=hidden -ffunction-sections -fdata-sections -Wno-error=format-security" NL_AUTOTOOLS_CFLAGS)
string(STRIP "${CMAKE_EXE_LINKER_FLAGS} -Wl,-z,max-page-size=16384" NL_AUTOTOOLS_LDFLAGS)
set(NL_AUTOTOOLS_HOST_ARG "")
if(NOT NL_HOST)
  string(APPEND NL_AUTOTOOLS_CC " --target=${NL_GNU_HOST}${ANDROID_PLATFORM_LEVEL}")
  if(CMAKE_SYSROOT)
    string(APPEND NL_AUTOTOOLS_CC " --sysroot=${CMAKE_SYSROOT}")
  endif()
  set(NL_AUTOTOOLS_HOST_ARG "--host=${NL_GNU_HOST}")
endif()
set(NL_AUTOTOOLS_ENV
  "CC=${NL_AUTOTOOLS_CC}"
  "CFLAGS=${NL_AUTOTOOLS_CFLAGS}"
  "LDFLAGS=${NL_AUTOTOOLS_LDFLAGS}"
  "AR=${CMAKE_AR}"
  "RANLIB=${CMAKE_RANLIB}"
  "NM=${CMAKE_NM}")

find_program(NL_MAKE NAMES gmake make REQUIRED)
cmake_host_system_information(RESULT NL_NPROC QUERY NUMBER_OF_LOGICAL_CORES)

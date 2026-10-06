# nlboot (MIT): libnlboot.so (JNI bridge for the app) + nljava executable.
# Standalone project: also built by the public nlauncher-android-natives repo.
cmake_minimum_required(VERSION 3.18)
project(nlboot C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

if(NOT ANDROID)
  # Host build: JNI headers from a desktop JDK.
  if(NOT NLBOOT_JNI_INCLUDE)
    if(DEFINED ENV{JAVA_HOME})
      set(NLBOOT_JNI_INCLUDE "$ENV{JAVA_HOME}/include")
    else()
      file(GLOB _jdk_incs /usr/lib/jvm/*/include)
      find_path(NLBOOT_JNI_INCLUDE jni.h PATHS ${_jdk_incs} /usr/lib/jvm/default-java/include NO_DEFAULT_PATH)
      if(NOT NLBOOT_JNI_INCLUDE)
        message(FATAL_ERROR "nlboot: jni.h not found — set JAVA_HOME or NLBOOT_JNI_INCLUDE")
      endif()
    endif()
  endif()
  set(_nlboot_inc ${NLBOOT_JNI_INCLUDE} ${NLBOOT_JNI_INCLUDE}/linux)
else()
  set(_nlboot_inc "")
endif()

set(_nlboot_warn -Wall -Wextra -Wno-unused-parameter)

add_library(nlboot SHARED nlboot.c nlboot_jni.c)
target_include_directories(nlboot PRIVATE ${CMAKE_CURRENT_SOURCE_DIR} ${_nlboot_inc})
target_compile_options(nlboot PRIVATE ${_nlboot_warn})

add_executable(nljava nlboot.c nlboot_main.c)
target_include_directories(nljava PRIVATE ${CMAKE_CURRENT_SOURCE_DIR} ${_nlboot_inc})
target_compile_options(nljava PRIVATE ${_nlboot_warn})

foreach(t nlboot nljava)
  target_link_libraries(${t} PRIVATE ${CMAKE_DL_LIBS})
  if(ANDROID)
    target_link_libraries(${t} PRIVATE log)
    # Android 15+: 16 KiB pages (NDK r28 does this by default, keep explicit).
    target_link_options(${t} PRIVATE "-Wl,-z,max-page-size=16384")
  else()
    find_package(Threads REQUIRED)
    target_link_libraries(${t} PRIVATE Threads::Threads)
  endif()
endforeach()

if(ANDROID)
  # Apps may only exec files from nativeLibraryDir, which the package manager
  # fills with lib*.so — so the executable is named like a library.
  set_target_properties(nljava PROPERTIES OUTPUT_NAME "libnljava.so" SUFFIX "")
endif()

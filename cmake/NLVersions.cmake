# Reads versions.env (KEY=VALUE lines) into CMake variables of the same name.
set(_nl_versions_file "${CMAKE_CURRENT_SOURCE_DIR}/versions.env")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${_nl_versions_file}")
file(STRINGS "${_nl_versions_file}" _nl_lines REGEX "^[A-Z0-9_]+=")
foreach(_line IN LISTS _nl_lines)
  string(REGEX MATCH "^([A-Z0-9_]+)=(.*)$" _ "${_line}")
  set(${CMAKE_MATCH_1} "${CMAKE_MATCH_2}")
endforeach()

foreach(_dir LWJGL_DIR LIBFFI_DIR FREETYPE_DIR HARFBUZZ_DIR JEMALLOC_DIR JNA_DIR)
  set(NL_${_dir} "${NL_SOURCES_DIR}/${${_dir}}")
endforeach()

if(NOT EXISTS "${NL_LWJGL_DIR}/modules/lwjgl/core/src/main/c")
  message(FATAL_ERROR "LWJGL sources not found in ${NL_LWJGL_DIR}. Run scripts/fetch-sources.sh first.")
endif()

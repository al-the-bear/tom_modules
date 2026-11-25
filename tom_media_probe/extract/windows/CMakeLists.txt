cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "tom_media_extract_probe")
project(${PROJECT_NAME} LANGUAGES CXX)

cmake_policy(VERSION 3.14...3.25)

set(PLUGIN_NAME "tom_media_extract_probe_plugin")

add_library(${PLUGIN_NAME} SHARED
  "include/tom_media_extract_probe/tom_media_extract_probe_plugin_c_api.h"
  "tom_media_extract_probe_plugin_c_api.cpp"
  "tom_media_extract_probe_plugin.cpp"
  "tom_media_extract_probe_plugin.h"
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
# Media Foundation and the Windows Imaging Component, both part of Windows.
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin
  mfplat mfreadwrite mfuuid propsys windowscodecs ole32 shlwapi)

set(tom_media_extract_probe_bundled_libraries
  ""
  PARENT_SCOPE
)

cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "tom_media_extract_probe")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "tom_media_extract_probe_plugin")

add_library(${PLUGIN_NAME} SHARED
  "tom_media_extract_probe_plugin.cc"
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)

# The system's GStreamer (LGPL): linked dynamically against the installed
# libraries, never bundled.
find_package(PkgConfig REQUIRED)
pkg_check_modules(GSTREAMER REQUIRED IMPORTED_TARGET
  gstreamer-1.0 gstreamer-app-1.0 gstreamer-pbutils-1.0)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GSTREAMER)

set(tom_media_extract_probe_bundled_libraries
  ""
  PARENT_SCOPE
)

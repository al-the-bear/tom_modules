//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <camera_desktop/camera_desktop_plugin.h>
#include <record_windows/record_windows_plugin_c_api.h>
#include <tom_media_extract_probe/tom_media_extract_probe_plugin_c_api.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  CameraDesktopPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("CameraDesktopPlugin"));
  RecordWindowsPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("RecordWindowsPluginCApi"));
  TomMediaExtractProbePluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("TomMediaExtractProbePluginCApi"));
}

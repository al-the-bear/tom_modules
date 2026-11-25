//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <camera_desktop/camera_desktop_plugin.h>
#include <record_linux/record_linux_plugin.h>
#include <tom_media_extract_probe/tom_media_extract_probe_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) camera_desktop_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "CameraDesktopPlugin");
  camera_desktop_plugin_register_with_registrar(camera_desktop_registrar);
  g_autoptr(FlPluginRegistrar) record_linux_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "RecordLinuxPlugin");
  record_linux_plugin_register_with_registrar(record_linux_registrar);
  g_autoptr(FlPluginRegistrar) tom_media_extract_probe_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "TomMediaExtractProbePlugin");
  tom_media_extract_probe_plugin_register_with_registrar(tom_media_extract_probe_registrar);
}

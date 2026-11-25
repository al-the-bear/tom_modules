#include "include/tom_media_extract_probe/tom_media_extract_probe_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "tom_media_extract_probe_plugin.h"

void TomMediaExtractProbePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  tom_media_extract_probe::TomMediaExtractProbePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

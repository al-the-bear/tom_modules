#ifndef FLUTTER_PLUGIN_TOM_MEDIA_EXTRACT_PROBE_PLUGIN_H_
#define FLUTTER_PLUGIN_TOM_MEDIA_EXTRACT_PROBE_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace tom_media_extract_probe {

class TomMediaExtractProbePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  TomMediaExtractProbePlugin();

  virtual ~TomMediaExtractProbePlugin();

  // Disallow copy and assign.
  TomMediaExtractProbePlugin(const TomMediaExtractProbePlugin&) = delete;
  TomMediaExtractProbePlugin& operator=(const TomMediaExtractProbePlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace tom_media_extract_probe

#endif  // FLUTTER_PLUGIN_TOM_MEDIA_EXTRACT_PROBE_PLUGIN_H_

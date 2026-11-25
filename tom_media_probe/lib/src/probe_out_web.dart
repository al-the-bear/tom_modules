import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:web/web.dart' as web;

/// The web has no folder: recordings are blobs and the report is printed.
Future<String> probeFolder() async => '';

Future<String?> writeReport(String name, String json) async => null;

String get platformName => 'web';

String get platformVersion => '';

int? get residentBytes => null;

void quit(int code) {}

Future<void> deleteFile(String path) async {}

final Map<String, String> _blobs = <String, String>{};

/// A bundled asset as something an extractor can open: a blob URL of its
/// content. The asset's own URL will not do: a `<video>` can only seek when
/// the server answers range requests, and Flutter's development server does
/// not.
Future<String> assetSource(String key) async {
  final String? known = _blobs[key];
  if (known != null) {
    return known;
  }
  final web.Response response = await web.window
      .fetch(ui_web.assetManager.getAssetUrl(key).toJS)
      .toDart;
  final web.Blob blob = await response.blob().toDart;
  return _blobs[key] = web.URL.createObjectURL(blob);
}

Future<int?> fileLength(String path) async => null;

bool fileExists(String path) => false;

Future<void> keepBytes(String name, List<int> bytes) async {}

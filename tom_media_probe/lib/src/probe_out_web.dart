/// The web has no folder: recordings are blobs and the report is printed.
Future<String> probeFolder() async => '';

Future<String?> writeReport(String name, String json) async => null;

String get platformName => 'web';

String get platformVersion => '';

int? get residentBytes => null;

void quit(int code) {}

Future<void> deleteFile(String path) async {}

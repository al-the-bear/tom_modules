import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A folder the probe may write recordings and its report into.
Future<String> probeFolder() async {
  final Directory base = await getTemporaryDirectory();
  final Directory dir = Directory('${base.path}/tom_media_probe');
  await dir.create(recursive: true);
  return dir.path;
}

/// Writes the report where the caller of an automated run finds it.
Future<String?> writeReport(String name, String json) async {
  final File file = File('${await probeFolder()}/$name');
  await file.writeAsString(json);
  return file.path;
}

String get platformName => Platform.operatingSystem;

String get platformVersion => Platform.operatingSystemVersion;

/// Resident memory of this process in bytes.
int? get residentBytes => ProcessInfo.currentRss;

Never quit(int code) => exit(code);

Future<void> deleteFile(String path) async {
  final File file = File(path);
  if (await file.exists()) {
    await file.delete();
  }
}

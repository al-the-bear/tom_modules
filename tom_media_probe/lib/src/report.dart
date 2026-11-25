import 'dart:convert';

import 'probe_out.dart';

/// Prints a report as `PROBE_PART <n> <json part>` lines (Android's log cuts
/// a line near 1,000 characters), writes it into the probe's folder, and
/// prints `PROBE_DONE <path>`. Answers the path.
Future<String?> emitReport(String fileName, Map<String, Object?> report) async {
  final String json = jsonEncode(report);
  final String? path = await writeReport(fileName, json);
  const int part = 700;
  for (int at = 0, n = 0; at < json.length; at += part, n++) {
    final int end = at + part < json.length ? at + part : json.length;
    // ignore: avoid_print
    print('PROBE_PART $n ${json.substring(at, end)}');
  }
  // ignore: avoid_print
  print('PROBE_DONE ${path ?? ''}');
  return path;
}

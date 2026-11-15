/// Printing a self-contained HTML document on a desktop, through the
/// platform's own print pipeline.
library;

import 'dart:convert';
import 'dart:io';

import 'print_html.dart';

/// Hands [html] to the platform's own print pipeline — a [TomPrintHtml].
///
/// The mechanism is deliberately the boring one: write the self-contained
/// document to a scratch file and open it with the OS opener, which lands in
/// the default browser, whose print dialog both prints and saves a PDF: one
/// rendering, laid out by the platform.
///
/// The file is *not* deleted afterwards: the opener returns as soon as the
/// handoff succeeds, long before the browser has read the file, and deleting
/// it here is a race whose loser is a blank print preview. It lands in the
/// OS scratch directory, which is the OS's to reclaim.
///
/// Answers where the job went, or null when the handoff failed.
Future<String?> tomPrintHtmlWithPlatform(String jobTitle, String html) async {
  final opener = switch (Platform.operatingSystem) {
    'macos' => ('open', <String>[]),
    'windows' => ('cmd', <String>['/c', 'start', '']),
    _ => ('xdg-open', <String>[]),
  };
  try {
    final scratch = await Directory.systemTemp.createTemp('tom_print_');
    final file = File('${scratch.path}/print.html');
    await file.writeAsString(html, encoding: utf8, flush: true);
    final result = await Process.run(opener.$1, [...opener.$2, file.path]);
    if (result.exitCode != 0) return null;
    return 'your browser — print or save as PDF from there';
  } on ProcessException {
    return null;
  } on FileSystemException {
    return null;
  }
}

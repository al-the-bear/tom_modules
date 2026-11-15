/// Printing a self-contained HTML document in a browser, selected at compile
/// time.
///
/// A library that imports `package:web` does not compile on the VM, so the
/// browser half sits behind a conditional import and the VM gets a stub.
library;

import 'browser_print_stub.dart'
    if (dart.library.js_interop) 'browser_print_web.dart';
import 'print_html.dart';

/// Lays [html] out for printing and opens the browser's print dialog; a
/// [TomPrintHtml]. Answers a short description, or null when this process
/// cannot print.
Future<String?> tomPrintHtmlInBrowser(String jobTitle, String html) =>
    printHtmlInBrowserImpl(jobTitle, html);

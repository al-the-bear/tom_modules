/// The browser half of `browser_print.dart`'s conditional import.
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Prints through a **hidden iframe**, not a new tab.
///
/// A new tab would be the obvious shape and it is the wrong one: the print
/// dialog is opened after an `await` (the user picked a scope first), by which
/// time the click that started it is no longer on the stack, and `window.open`
/// from outside a user gesture is what popup blockers exist to stop. An iframe
/// in the current document needs no gesture at all.
Future<String?> printHtmlInBrowserImpl(String jobTitle, String html) async {
  final frame = web.document.createElement('iframe') as web.HTMLIFrameElement;
  frame.style
    ..position = 'fixed'
    ..right = '0'
    ..bottom = '0'
    ..width = '0'
    ..height = '0'
    ..border = '0';
  frame.srcdoc = html.toJS;
  final done = Completer<void>();
  frame.onload = ((web.Event _) {
    // `print()` blocks until the dialog is dismissed in every engine this
    // build targets, so the frame is only removed once the user is finished
    // with it — removing it earlier would tear the document out from under the
    // preview.
    frame.contentWindow?.print();
    frame.remove();
    if (!done.isCompleted) done.complete();
  }).toJS;
  web.document.body!.append(frame);
  await done.future;
  return 'your browser‘s print dialog';
}

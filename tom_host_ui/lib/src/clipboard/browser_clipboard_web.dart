/// The browser half of `browser_clipboard.dart`'s conditional import.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// One `ClipboardItem` carrying both MIME types — the API takes them together,
/// so there is no ordering in which one erases the other.
Future<bool> placeBothFlavoursImpl({
  required String html,
  required String text,
}) async {
  try {
    final flavours = JSObject()
      ..setProperty(
        'text/html'.toJS,
        web.Blob([html.toJS].toJS, web.BlobPropertyBag(type: 'text/html')),
      )
      ..setProperty(
        'text/plain'.toJS,
        web.Blob([text.toJS].toJS, web.BlobPropertyBag(type: 'text/plain')),
      );
    await web.window.navigator.clipboard
        .write([web.ClipboardItem(flavours)].toJS)
        .toDart;
    return true;
  } on Object {
    // A refused permission, an insecure origin, or an engine without the async
    // clipboard API. All three are "this browser would not take it", which is
    // what the caller reports.
    return false;
  }
}

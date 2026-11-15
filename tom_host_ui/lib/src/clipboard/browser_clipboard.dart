/// Both clipboard flavours in a browser, selected at compile time.
///
/// A library that imports `package:web` does not compile on the VM, so the
/// browser half sits behind a conditional import and the VM gets a stub —
/// which is what lets a `flutter test` of a web application load at all.
library;

import 'browser_clipboard_stub.dart'
    if (dart.library.js_interop) 'browser_clipboard_web.dart';
import 'clipboard_placement.dart';

/// Writes both flavours to the system clipboard in one `ClipboardItem`; a
/// [TomPlaceOnClipboard].
///
/// [TomClipboardPlacement.both] when both landed, otherwise
/// [TomClipboardPlacement.failed]. The browser clipboard API takes the
/// flavours *together* by construction, so there is no way to express "HTML
/// only" and lose the plain text — and no plain-only outcome either.
Future<TomClipboardPlacement> tomPlaceOnBrowserClipboard({
  required String html,
  required String text,
}) async => await placeBothFlavoursImpl(html: html, text: text)
    ? TomClipboardPlacement.both
    : TomClipboardPlacement.failed;

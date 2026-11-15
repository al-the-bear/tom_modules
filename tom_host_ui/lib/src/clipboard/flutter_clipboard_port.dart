/// The portable binding of `tom_basics`' `TomClipboardPort`, over Flutter's
/// own `Clipboard`.
///
/// Flutter's clipboard carries plain text and no flags, so this binding marks
/// nothing concealed and recognises its own value by **comparing text**: the
/// clear runs only while the clipboard's text is still the copied value. That
/// is the honest floor every platform has. A host that can do better binds
/// its own port — `TomDesktopClipboardPort` (`desktop.dart`) marks the value
/// concealed on macOS and compares the pasteboard's change count.
library;

import 'package:flutter/services.dart';
import 'package:tom_basics/utilities.dart';

/// [TomClipboardPort] over `Clipboard.setData` / `getData`.
class TomFlutterClipboardPort implements TomClipboardPort {
  const TomFlutterClipboardPort();

  @override
  Future<TomClipboardReceipt?> placeConcealed(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return TomClipboardReceipt(text);
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<bool> clearIfHolding(TomClipboardReceipt receipt) async {
    try {
      final held = await Clipboard.getData(Clipboard.kTextPlain);
      if (held?.text != receipt.text) return false;
      // Flutter has no "clear"; an empty text flavor is the clear it offers.
      await Clipboard.setData(const ClipboardData(text: ''));
      return true;
    } on PlatformException {
      return false;
    }
  }
}

/// The desktop binding of `tom_basics`' `TomClipboardPort`: a copied protected
/// value marked concealed where the platform has a flag for it.
///
/// What each platform does:
///
/// * **macOS** — the host's runner places the text together with the
///   `org.nspasteboard.ConcealedType` and `org.nspasteboard.TransientType`
///   markers (nspasteboard.org), which clipboard managers honour by not
///   recording the item, and answers the pasteboard's `changeCount`. The clear
///   compares that count, so it also leaves alone the same text copied again
///   from elsewhere. Over [TomDesktopClipboardPort.channel], methods
///   `placeConcealed` (`text` → the new change count) and `clearIfUnchanged`
///   (`changeCount` → a bool) — native code the host application provides
///   (README, "What a host application provides").
/// * **Windows** — plain text through Flutter's clipboard. The
///   `ExcludeClipboardContentFromMonitorProcessing` /
///   `CanIncludeInClipboardHistory` formats that would keep it out of Win+V
///   history and cloud clipboard are **not** set: the value can appear in
///   clipboard history until the clear replaces it.
/// * **Linux** — plain text through Flutter's clipboard. There is no
///   cross-desktop concealed flag (KDE's `x-kde-passwordManagerHint` is the
///   nearest); a clipboard manager may record the value.
/// * **A host whose runner does not answer the channel** gets the portable
///   binding: plain text, cleared while the text still matches.
///
/// Every platform clears after the configured delay, and only while the
/// clipboard still holds the copied value; that part is `TomProtectedClipboard`'s.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:tom_basics/utilities.dart';

import 'flutter_clipboard_port.dart';

/// [TomClipboardPort] for desktop hosts.
class TomDesktopClipboardPort implements TomClipboardPort {
  /// The channel the host's macOS runner answers.
  final MethodChannel channel;

  /// `Platform.operatingSystem` unless a test says otherwise.
  final String? platform;

  /// What a platform without a concealed flag, or a runner without the
  /// channel, falls back to.
  final TomClipboardPort fallback;

  const TomDesktopClipboardPort({
    required this.channel,
    this.platform,
    this.fallback = const TomFlutterClipboardPort(),
  });

  bool get _macOS => (platform ?? Platform.operatingSystem) == 'macos';

  @override
  Future<TomClipboardReceipt?> placeConcealed(String text) async {
    if (_macOS) {
      try {
        final count = await channel.invokeMethod<int>('placeConcealed', {
          'text': text,
        });
        if (count != null) {
          return TomClipboardReceipt(text, generation: count);
        }
      } on MissingPluginException {
        // Not a runner that answers: the portable floor below.
      } on PlatformException {
        return null;
      }
    }
    return fallback.placeConcealed(text);
  }

  @override
  Future<bool> clearIfHolding(TomClipboardReceipt receipt) async {
    final generation = receipt.generation;
    if (_macOS && generation != null) {
      try {
        return await channel.invokeMethod<bool>('clearIfUnchanged', {
              'changeCount': generation,
            }) ??
            false;
      } on MissingPluginException {
        // Placed through the channel and cleared without it cannot happen in
        // one process; fall through to the text comparison all the same.
      } on PlatformException {
        return false;
      }
    }
    return fallback.clearIfHolding(receipt);
  }
}

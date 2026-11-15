/// What a host managed to put on the clipboard, and the one function shape
/// that places both flavours.
library;

/// What a host managed to put on the clipboard.
///
/// A copy with formatting owes both flavours, so a host that can only place
/// one has to be able to *say* so: the alternative is a paste that silently
/// lost its formatting, which is indistinguishable to the user from the
/// feature not working.
enum TomClipboardPlacement {
  /// HTML and plain text, together.
  both,

  /// Plain text only — this platform has no rich flavour available.
  plainTextOnly,

  /// Nothing was placed.
  failed,
}

/// Places **both** flavours in one act.
///
/// One function taking both rather than two functions taking one each: a
/// clipboard is last-writer-wins, so two calls are a race in which the second
/// flavour erases the first. The signature is what makes "both flavours
/// always" the only thing a host *can* implement.
typedef TomPlaceOnClipboard =
    Future<TomClipboardPlacement> Function({
      required String html,
      required String text,
    });

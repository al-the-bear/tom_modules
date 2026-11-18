/// Why a frame or a message was refused.
enum OfficeProtocolErrorCode {
  /// The frame's type byte names no message of this protocol.
  unknownType,

  /// A header that is not a JSON object, a field missing or of the wrong
  /// kind, or raw bytes that do not fit the message.
  malformed,

  /// A frame longer than the reader accepts, or shorter than its own header.
  badLength,

  /// The stream ended inside a frame.
  truncated,
}

/// A frame or message the codec refuses.
final class OfficeProtocolException implements Exception {
  /// An exception with its [code] and a [message] for the trail.
  const OfficeProtocolException(this.code, this.message);

  /// Why.
  final OfficeProtocolErrorCode code;

  /// What, in words.
  final String message;

  @override
  String toString() => 'OfficeProtocolException(${code.name}): $message';
}

/// A helper whose `hello` names another protocol number than this side's.
/// Forge refuses such a helper and reports it in the tab.
final class OfficeProtocolVersionMismatch implements Exception {
  /// The mismatch between [expected] (this side) and [actual] (the helper's).
  const OfficeProtocolVersionMismatch(this.expected, this.actual);

  /// The protocol number this side speaks.
  final int expected;

  /// The number the helper sent.
  final int actual;

  @override
  String toString() =>
      'OfficeProtocolVersionMismatch: the helper speaks protocol $actual, '
      'this side protocol $expected';
}

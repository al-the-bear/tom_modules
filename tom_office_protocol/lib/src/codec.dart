import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'errors.dart';
import 'messages.dart';

/// Encodes messages to frames and decodes frames to messages.
///
/// A frame on the helper's stdin and stdout is:
///
/// | Bytes | Holds |
/// | --- | --- |
/// | 4 | the length of everything after these 4 bytes, big-endian |
/// | 1 | the message type ([OfficeMessageType.code]) |
/// | n | the JSON header (UTF-8), one line: JSON text never holds a raw line break |
/// | 1 | `0x0A`, ending the header |
/// | rest | the raw bytes: the pixels of `tile` and `windowPixels`, else none |
class OfficeProtocolCodec {
  /// A codec that refuses frames longer than [maxFrameLength] bytes.
  const OfficeProtocolCodec({this.maxFrameLength = defaultMaxFrameLength});

  /// 256 MiB: far above a full-screen window's pixels (a 4K window is
  /// 32 MiB).
  static const defaultMaxFrameLength = 256 * 1024 * 1024;

  /// The longest frame accepted, not counting its 4-byte length.
  final int maxFrameLength;

  /// The frame of [message].
  Uint8List encode(OfficeMessage message) {
    switch (message) {
      case OfficeTile():
        message.checkPixels();
      case OfficeWindowPixels():
        message.checkPixels();
      default:
        break;
    }
    final header = utf8.encode(jsonEncode(message.toJson()));
    final raw = message.bytes;
    final length = 1 + header.length + 1 + raw.length;
    if (length > maxFrameLength) {
      throw OfficeProtocolException(
        OfficeProtocolErrorCode.badLength,
        '${message.messageType.tableName}: a frame of $length bytes is longer '
        'than $maxFrameLength',
      );
    }
    final frame = Uint8List(4 + length);
    ByteData.sublistView(frame).setUint32(0, length);
    frame[4] = message.messageType.code;
    frame.setRange(5, 5 + header.length, header);
    frame[5 + header.length] = 0x0A;
    frame.setRange(6 + header.length, frame.length, raw);
    return frame;
  }

  /// The message of one whole [frame], its 4-byte length included.
  OfficeMessage decode(Uint8List frame) {
    if (frame.length < 4) {
      throw const OfficeProtocolException(
        OfficeProtocolErrorCode.truncated,
        'a frame needs its 4-byte length',
      );
    }
    final length = ByteData.sublistView(frame).getUint32(0);
    if (frame.length != 4 + length) {
      throw OfficeProtocolException(
        OfficeProtocolErrorCode.badLength,
        'the frame says $length bytes, it holds ${frame.length - 4}',
      );
    }
    return decodeBody(Uint8List.sublistView(frame, 4));
  }

  /// The message of a frame's [body]: everything after its 4-byte length.
  OfficeMessage decodeBody(Uint8List body) {
    if (body.isEmpty) {
      throw const OfficeProtocolException(
        OfficeProtocolErrorCode.badLength,
        'an empty frame has no type',
      );
    }
    final type = OfficeMessageType.fromCode(body[0]);
    if (type == null) {
      throw OfficeProtocolException(
        OfficeProtocolErrorCode.unknownType,
        'message type ${body[0]} is not in protocol $kOfficeProtocolVersion',
      );
    }
    final end = body.indexOf(0x0A, 1);
    if (end < 0) {
      throw OfficeProtocolException(
        OfficeProtocolErrorCode.malformed,
        '${type.tableName}: the header has no end',
      );
    }
    final Object? header;
    try {
      header = jsonDecode(utf8.decode(Uint8List.sublistView(body, 1, end)));
    } on FormatException catch (e) {
      throw OfficeProtocolException(
        OfficeProtocolErrorCode.malformed,
        '${type.tableName}: the header is not JSON (${e.message})',
      );
    }
    if (header is! Map<String, Object?>) {
      throw OfficeProtocolException(
        OfficeProtocolErrorCode.malformed,
        '${type.tableName}: the header is not a JSON object',
      );
    }
    return OfficeMessage.fromJson(
      type,
      header,
      Uint8List.fromList(Uint8List.sublistView(body, end + 1)),
    );
  }

  /// Checks a helper's [hello]: throws [OfficeProtocolVersionMismatch] when
  /// it speaks another protocol than [expected].
  static void checkHello(
    OfficeHello hello, {
    int expected = kOfficeProtocolVersion,
  }) {
    if (hello.protocol != expected) {
      throw OfficeProtocolVersionMismatch(expected, hello.protocol);
    }
  }

  /// The messages of a byte stream (a process's stdout), however its frames
  /// are split across reads. A refused frame ends the stream with its
  /// [OfficeProtocolException]; so does a stream that ends inside a frame.
  Stream<OfficeMessage> decodeStream(Stream<List<int>> bytes) async* {
    final reader = OfficeFrameReader(this);
    await for (final chunk in bytes) {
      yield* Stream.fromIterable(reader.add(chunk));
    }
    reader.close();
  }
}

/// Collects bytes as they arrive and gives the whole frames among them.
///
/// ```dart
/// final reader = OfficeFrameReader(const OfficeProtocolCodec());
/// process.stdout.listen((chunk) => reader.add(chunk).forEach(handle));
/// ```
class OfficeFrameReader {
  /// A reader decoding with [codec].
  OfficeFrameReader([this.codec = const OfficeProtocolCodec()]);

  /// The codec frames are decoded with.
  final OfficeProtocolCodec codec;

  final _buffer = BytesBuilder(copy: true);
  int? _length;

  /// The bytes held that do not make a whole frame yet.
  int get pending => _buffer.length;

  /// Takes [chunk] and returns the messages of the frames it completes, in
  /// order. Throws [OfficeProtocolException] for a refused frame; the reader
  /// is not usable after that.
  List<OfficeMessage> add(List<int> chunk) {
    _buffer.add(chunk);
    final messages = <OfficeMessage>[];
    while (true) {
      if (_length == null) {
        if (_buffer.length < 4) break;
        final bytes = _buffer.takeBytes();
        final length = ByteData.sublistView(bytes).getUint32(0);
        if (length == 0 || length > codec.maxFrameLength) {
          throw OfficeProtocolException(
            OfficeProtocolErrorCode.badLength,
            'a frame of $length bytes (at most ${codec.maxFrameLength})',
          );
        }
        _length = length;
        _buffer.add(Uint8List.sublistView(bytes, 4));
      }
      final length = _length!;
      if (_buffer.length < length) break;
      final bytes = _buffer.takeBytes();
      _length = null;
      messages.add(codec.decodeBody(Uint8List.sublistView(bytes, 0, length)));
      if (bytes.length > length) {
        _buffer.add(Uint8List.sublistView(bytes, length));
      }
    }
    return messages;
  }

  /// Ends the input: throws [OfficeProtocolException] when a frame was left
  /// unfinished.
  void close() {
    if (_length != null || _buffer.isNotEmpty) {
      throw OfficeProtocolException(
        OfficeProtocolErrorCode.truncated,
        'the stream ended inside a frame (${_buffer.length} bytes held)',
      );
    }
  }
}

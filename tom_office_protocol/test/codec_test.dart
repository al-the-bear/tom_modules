import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tom_office_protocol/tom_office_protocol.dart';

Uint8List _pixels(int w, int h) =>
    Uint8List.fromList(List.generate(w * h * 4, (i) => (i * 7) % 256));

/// One message of every type, with every field set to a value that is not
/// its default, and the optional ones both set and unset where they can be.
final List<OfficeMessage> samples = [
  const OfficeHello(
    helperVersion: '0.1.0',
    lokVersion: '{"ProductName":"LibreOffice","ProductVersion":"26.8"}',
    pid: 4242,
  ),
  const OfficeOpen(
    path: '/docs/report é.docx',
    readOnly: true,
    language: 'de-DE',
  ),
  const OfficeOpened(
    docType: OfficeDocType.spreadsheet,
    parts: 3,
    partNames: ['Sheet1', 'Daten', 'Σ'],
    currentPart: 1,
    width: 12000,
    height: 30000,
    tileMode: OfficePixelFormat.bgra,
  ),
  const OfficeOpened(
    docType: OfficeDocType.text,
    parts: 1,
    partNames: [''],
    currentPart: 0,
    width: 11906,
    height: 16838,
    tileMode: OfficePixelFormat.bgra,
    readOnly: true,
    lockedBy: 'Ann Other',
  ),
  const OfficePasswordNeeded(toModify: true),
  const OfficePassword(password: 's3cret'),
  const OfficePassword(password: null),
  const OfficeRenderTile(
    id: 7,
    part: 0,
    x: 3840,
    y: 7680,
    w: 3840,
    h: 3840,
    pxW: 256,
    pxH: 256,
  ),
  OfficeTile(
    id: 7,
    part: 0,
    x: 3840,
    y: 7680,
    w: 3840,
    h: 3840,
    pxW: 16,
    pxH: 8,
    format: OfficePixelFormat.bgra,
    pixels: _pixels(16, 8),
  ),
  const OfficeKey(type: OfficeKeyEventType.up, charCode: 65, keyCode: 512),
  const OfficeTextInput(type: OfficeTextInputType.end, text: 'ü日本'),
  const OfficeMouse(
    type: OfficeMouseEventType.move,
    x: 100,
    y: 200,
    count: 2,
    buttons: 4,
    modifiers: 4096,
  ),
  const OfficeSelection(kind: OfficeSelectionKind.graphic, type: 1, x: 5, y: 6),
  const OfficeSelection(kind: OfficeSelectionKind.reset),
  const OfficeUno(
    id: 8,
    command: '.uno:CharFontName',
    args: '{"CharFontName.FamilyName":{"type":"string","value":"Arial"}}',
  ),
  const OfficeCommandValues(id: 9, command: '.uno:StyleApply'),
  const OfficeValues(id: 9, json: '{"commandName":".uno:StyleApply"}'),
  const OfficeView(
    part: 2,
    visibleArea: OfficeRect(0, 1440, 20000, 12000),
    zoom: 0.0177,
  ),
  const OfficeSetPart(part: 2),
  const OfficeCallback(type: 'INVALIDATE_TILES', payload: '0, 0, 1000, 2000'),
  const OfficeSave(
    id: 10,
    targetPath: '/docs/.report.docx.tom-save-1',
    format: 'docx',
    filterOptions: 'TakeOwnership',
  ),
  const OfficeSaved(id: 10, ok: false, error: 'disk full'),
  const OfficeSaved(id: 11, ok: true),
  const OfficeWindowOpened(
    windowId: 5,
    kind: 'dialog',
    title: 'Format Cells',
    width: 640,
    height: 480,
    parentId: 1,
  ),
  const OfficeWindowOpened(
    windowId: 6,
    kind: 'tooltip',
    title: '',
    width: 10,
    height: 10,
  ),
  const OfficeWindowChanged(
    windowId: 5,
    action: 'invalidate',
    rectangle: OfficeRect(1, 2, 3, 4),
  ),
  const OfficeWindowChanged(windowId: 5, action: 'close'),
  const OfficePaintWindow(
    id: 12,
    windowId: 5,
    x: 0,
    y: 0,
    w: 640,
    h: 480,
    dpiScale: 2.0,
  ),
  OfficeWindowPixels(
    id: 12,
    windowId: 5,
    x: 0,
    y: 0,
    w: 4,
    h: 3,
    format: OfficePixelFormat.rgba,
    pixels: _pixels(4, 3),
  ),
  const OfficeWindowMouse(
    windowId: 5,
    type: OfficeMouseEventType.down,
    x: 10,
    y: 20,
    count: 1,
    buttons: 1,
    modifiers: 0,
  ),
  const OfficeWindowKey(
    windowId: 5,
    type: OfficeKeyEventType.down,
    charCode: 13,
    keyCode: 1280,
  ),
  const OfficeWindowTextInput(
    windowId: 5,
    type: OfficeTextInputType.input,
    text: 'abc',
  ),
  const OfficeWindowClose(windowId: 5),
  const OfficeJsDialog(json: '{"jsontype":"dialog","id":"5"}'),
  const OfficeDialogEvent(
    windowId: 5,
    json: '{"id":"ok","cmd":"click","data":""}',
  ),
  const OfficeDialogModeMessage(mode: OfficeDialogMode.json),
  const OfficePing(id: 13),
  const OfficePong(id: 13),
  const OfficeClose(),
  const OfficeClosed(),
  const OfficeError(id: 8, code: 'unoFailed', message: 'no such command'),
  const OfficeError(code: 'loadFailed', message: 'General input/output error'),
  const OfficeCopy(id: 14, mimeTypes: ['text/html']),
  const OfficeClipboard(
    id: 14,
    data: {'text/plain;charset=utf-8': 'Hallo\nWelt', 'text/html': '<b>x</b>'},
  ),
  const OfficePaste(mimeType: 'text/html', data: '<p>pasted</p>'),
];

void main() {
  const codec = OfficeProtocolCodec();

  group('OFFICE-PROTO-TABLE the message table', () {
    test(
      'OFFICE-PROTO-TABLE-1: every message type of the table has a sample',
      () {
        expect(
          samples.map((m) => m.messageType).toSet(),
          OfficeMessageType.values.toSet(),
        );
      },
    );

    test('OFFICE-PROTO-TABLE-2: the table names, the dialog and clipboard '
        'messages included', () {
      expect(OfficeMessageType.values.map((t) => t.tableName).toList(), [
        'hello', 'open', 'opened', 'passwordNeeded', 'password', //
        'renderTile', 'tile', 'key', 'textInput', 'mouse', 'selection', //
        'uno', 'commandValues', 'values', 'view', 'setPart', 'callback', //
        'save', 'saved', 'windowOpened', 'windowChanged', 'paintWindow', //
        'windowPixels', 'windowMouse', 'windowKey', 'windowTextInput', //
        'windowClose', 'jsDialog', 'dialogEvent', 'dialogMode', 'ping', //
        'pong', 'close', 'closed', 'error', 'copy', 'clipboard', 'paste',
      ]);
    });

    test('OFFICE-PROTO-TABLE-3: type codes are unique and one byte', () {
      final codes = OfficeMessageType.values.map((t) => t.code).toList();
      expect(codes.toSet().length, codes.length);
      expect(codes.every((c) => c > 0 && c < 256), isTrue);
    });

    test('OFFICE-PROTO-TABLE-4: the class side matches the direction', () {
      for (final m in samples) {
        expect(
          m is OfficeHelperCommand,
          m.messageType.direction == OfficeDirection.toHelper,
          reason: m.messageType.tableName,
        );
        expect(
          m is OfficeHelperEvent,
          m.messageType.direction == OfficeDirection.toForge,
          reason: m.messageType.tableName,
        );
      }
    });

    test(
      'OFFICE-PROTO-TABLE-5: the protocol number is 1, and hello sends it',
      () {
        expect(kOfficeProtocolVersion, 1);
        expect(
          const OfficeHello(
            helperVersion: 'x',
            lokVersion: '{}',
            pid: 1,
          ).protocol,
          1,
        );
      },
    );
  });

  group('OFFICE-PROTO-RT round trip through the codec', () {
    for (final (i, message) in samples.indexed) {
      test('OFFICE-PROTO-RT-${i + 1}: ${message.messageType.tableName}', () {
        final frame = codec.encode(message);
        final decoded = codec.decode(frame);
        expect(decoded.runtimeType, message.runtimeType);
        expect(decoded, message);
        expect(decoded.toJson(), message.toJson());
        expect(decoded.bytes, message.bytes);
        expect(codec.encode(decoded), frame);
      });
    }
  });

  group('OFFICE-PROTO-FRAME the frame layout', () {
    test('OFFICE-PROTO-FRAME-1: length, type, one-line JSON header, raw '
        'bytes', () {
      final tile = samples.whereType<OfficeTile>().single;
      final frame = codec.encode(tile);
      final data = ByteData.sublistView(frame);
      expect(data.getUint32(0), frame.length - 4);
      expect(frame[4], OfficeMessageType.tile.code);
      final end = frame.indexOf(0x0A, 5);
      expect(jsonDecode(utf8.decode(frame.sublist(5, end))), tile.toJson());
      expect(frame.sublist(end + 1), tile.pixels);
    });

    test('OFFICE-PROTO-FRAME-2: a header with line breaks in its text stays '
        'one line', () {
      const paste = OfficePaste(mimeType: 'text/plain', data: 'a\nb\r\nc');
      final frame = codec.encode(paste);
      expect(frame.indexOf(0x0A, 5), frame.length - 1);
      expect(codec.decode(frame), paste);
    });
  });

  group('OFFICE-PROTO-SPLIT frames split across reads', () {
    final stream = Uint8List.fromList([
      for (final m in samples) ...codec.encode(m),
    ]);

    test('OFFICE-PROTO-SPLIT-1: byte by byte', () {
      final reader = OfficeFrameReader(codec);
      final got = <OfficeMessage>[];
      for (final b in stream) {
        got.addAll(reader.add([b]));
      }
      reader.close();
      expect(got, samples);
    });

    test('OFFICE-PROTO-SPLIT-2: chunks of every size from 1 to 64', () {
      for (var size = 1; size <= 64; size++) {
        final reader = OfficeFrameReader(codec);
        final got = <OfficeMessage>[];
        for (var at = 0; at < stream.length; at += size) {
          got.addAll(
            reader.add(stream.sublist(at, (at + size).clamp(0, stream.length))),
          );
        }
        reader.close();
        expect(got, samples, reason: 'chunk size $size');
      }
    });

    test('OFFICE-PROTO-SPLIT-3: all frames in one read', () {
      final reader = OfficeFrameReader(codec);
      expect(reader.add(stream), samples);
      expect(reader.pending, 0);
    });

    test('OFFICE-PROTO-SPLIT-4: decodeStream over a split stream', () async {
      final chunks = [
        for (var at = 0; at < stream.length; at += 37)
          stream.sublist(at, (at + 37).clamp(0, stream.length)),
      ];
      expect(
        await codec.decodeStream(Stream.fromIterable(chunks)).toList(),
        samples,
      );
    });

    test('OFFICE-PROTO-SPLIT-5: a stream that ends inside a frame is '
        'reported', () async {
      final cut = stream.sublist(0, stream.length - 3);
      await expectLater(
        codec.decodeStream(Stream.value(cut)).toList(),
        throwsA(
          isA<OfficeProtocolException>().having(
            (e) => e.code,
            'code',
            OfficeProtocolErrorCode.truncated,
          ),
        ),
      );
    });
  });

  group('OFFICE-PROTO-REFUSE refused frames', () {
    Matcher refused(OfficeProtocolErrorCode code) => throwsA(
      isA<OfficeProtocolException>().having((e) => e.code, 'code', code),
    );

    Uint8List frame(int type, String header, [List<int> raw = const []]) {
      final body = [type, ...utf8.encode(header), 0x0A, ...raw];
      return Uint8List.fromList([
        ...(ByteData(4)..setUint32(0, body.length)).buffer.asUint8List(),
        ...body,
      ]);
    }

    test('OFFICE-PROTO-REFUSE-1: an unknown type', () {
      expect(
        () => codec.decode(frame(200, '{}')),
        refused(OfficeProtocolErrorCode.unknownType),
      );
      expect(
        () => codec.decode(frame(0, '{}')),
        refused(OfficeProtocolErrorCode.unknownType),
      );
      expect(
        () => OfficeFrameReader(codec).add(frame(99, '{}')),
        refused(OfficeProtocolErrorCode.unknownType),
      );
    });

    test('OFFICE-PROTO-REFUSE-2: a missing or wrong field', () {
      final ping = OfficeMessageType.ping.code;
      expect(
        () => codec.decode(frame(ping, '{}')),
        refused(OfficeProtocolErrorCode.malformed),
      );
      expect(
        () => codec.decode(frame(ping, '{"id":"7"}')),
        refused(OfficeProtocolErrorCode.malformed),
      );
      expect(
        () => codec.decode(
          frame(OfficeMessageType.dialogMode.code, '{"mode":"html"}'),
        ),
        refused(OfficeProtocolErrorCode.malformed),
      );
    });

    test('OFFICE-PROTO-REFUSE-3: a header that is not a JSON object', () {
      final ping = OfficeMessageType.ping.code;
      expect(
        () => codec.decode(frame(ping, '[1]')),
        refused(OfficeProtocolErrorCode.malformed),
      );
      expect(
        () => codec.decode(frame(ping, '{"id":')),
        refused(OfficeProtocolErrorCode.malformed),
      );
    });

    test('OFFICE-PROTO-REFUSE-4: pixels that do not fit, or raw bytes on a '
        'message without', () {
      final tile = samples.whereType<OfficeTile>().single;
      expect(
        () => codec.decode(
          frame(OfficeMessageType.tile.code, jsonEncode(tile.toJson()), [1, 2]),
        ),
        refused(OfficeProtocolErrorCode.malformed),
      );
      expect(
        () => codec.decode(frame(OfficeMessageType.pong.code, '{"id":1}', [9])),
        refused(OfficeProtocolErrorCode.malformed),
      );
      expect(
        () => codec.encode(
          OfficeWindowPixels(
            id: 1,
            windowId: 1,
            x: 0,
            y: 0,
            w: 2,
            h: 2,
            format: OfficePixelFormat.bgra,
            pixels: Uint8List(3),
          ),
        ),
        refused(OfficeProtocolErrorCode.malformed),
      );
    });

    test('OFFICE-PROTO-REFUSE-5: a frame longer than allowed', () {
      const small = OfficeProtocolCodec(maxFrameLength: 64);
      final big = codec.encode(OfficePaste(mimeType: 'x', data: 'y' * 100));
      expect(
        () => OfficeFrameReader(small).add(big),
        refused(OfficeProtocolErrorCode.badLength),
      );
      expect(
        () => small.encode(OfficePaste(mimeType: 'x', data: 'y' * 100)),
        refused(OfficeProtocolErrorCode.badLength),
      );
      expect(
        () => codec.decode(Uint8List.sublistView(big, 0, big.length - 1)),
        refused(OfficeProtocolErrorCode.badLength),
      );
    });

    test('OFFICE-PROTO-REFUSE-7: an opened header without the 0.2.0 fields '
        'reads them as absent', () {
      final m =
          codec.decode(
                frame(
                  OfficeMessageType.opened.code,
                  '{"docType":"text","parts":1,"partNames":["a"],"currentPart":0,'
                  '"width":1,"height":2,"tileMode":"bgra"}',
                ),
              )
              as OfficeOpened;
      expect(m.readOnly, isFalse);
      expect(m.lockedBy, isNull);
    });

    test('OFFICE-PROTO-REFUSE-6: unknown fields are ignored (fields are only '
        'added)', () {
      final m = codec.decode(
        frame(OfficeMessageType.ping.code, '{"id":3,"later":true}'),
      );
      expect(m, const OfficePing(id: 3));
    });
  });

  group('OFFICE-PROTO-VERSION the protocol number', () {
    test('OFFICE-PROTO-VERSION-1: a hello of this protocol passes', () {
      OfficeProtocolCodec.checkHello(
        const OfficeHello(helperVersion: '0.1.0', lokVersion: '{}', pid: 1),
      );
    });

    test('OFFICE-PROTO-VERSION-2: a hello of another protocol is reported', () {
      final hello =
          codec.decode(
                codec.encode(
                  const OfficeHello(
                    protocol: 2,
                    helperVersion: '0.2.0',
                    lokVersion: '{}',
                    pid: 1,
                  ),
                ),
              )
              as OfficeHello;
      expect(
        () => OfficeProtocolCodec.checkHello(hello),
        throwsA(
          isA<OfficeProtocolVersionMismatch>()
              .having((e) => e.expected, 'expected', 1)
              .having((e) => e.actual, 'actual', 2),
        ),
      );
    });
  });

  test('OFFICE-PROTO-REDACT-1: a password never shows in toString', () {
    expect(
      const OfficePassword(password: 's3cret').toString(),
      isNot(contains('s3cret')),
    );
    expect(const OfficePassword(password: null).toString(), contains('cancel'));
  });
}

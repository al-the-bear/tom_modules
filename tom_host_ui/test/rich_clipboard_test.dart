/// `TomRichClipboard` — both flavours in one act, and the pure builders it
/// sends: the CF_HTML payload with its byte offsets, the Windows line endings,
/// the macOS AppleScript program.
///
/// No clipboard is written by this suite: a suite that destroys the clipboard
/// of whoever runs it pays a real cost for a weak claim. What is tested is
/// what can be *wrong* — pure functions of two strings — and what the flow
/// does with each answer a runner can give, over a channel the test answers
/// itself. The runners' own halves are native code in the host application.
///
/// Test ids are those the guarantees were first written under (WONEPRPD23,
/// WONEPRPC20), so the records that cite them still find them.
@Timeout(Duration(seconds: 60))
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_host_ui/desktop.dart';

const _channel = MethodChannel('test/clipboard');

Future<TomClipboardPlacement> _place({
  required String html,
  required String text,
  required String platform,
}) => TomRichClipboard(
  channel: _channel,
  platform: platform,
).place(html: html, text: text);

/// A CF_HTML payload taken apart the way a reader takes it apart: by the
/// numbers in its descriptor, applied to its bytes.
class _CfHtml {
  _CfHtml(this.bytes) {
    final head = latin1.decode(bytes.sublist(0, 200.clamp(0, bytes.length)));
    for (final name in [
      'StartHTML',
      'EndHTML',
      'StartFragment',
      'EndFragment',
    ]) {
      offsets[name] = int.parse(
        RegExp('$name:(\\d+)\r\n').firstMatch(head)!.group(1)!,
      );
    }
    version = RegExp('^Version:([0-9.]+)\r\n').firstMatch(head)!.group(1)!;
  }

  final Uint8List bytes;
  final offsets = <String, int>{};
  late final String version;

  String get html =>
      utf8.decode(bytes.sublist(offsets['StartHTML']!, offsets['EndHTML']!));
  String get fragment => utf8.decode(
    bytes.sublist(offsets['StartFragment']!, offsets['EndFragment']!),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WONEPRPD23 — the CF_HTML payload', () {
    test('WONEPRPD23-1: the four offsets are byte offsets, and they select '
        'what they name', () {
      const html =
          '<html><head><meta charset="utf-8"></head>'
          '<body><h1>Grüße — π</h1><p>He said "hi".</p></body></html>';
      final cf = _CfHtml(tomCfHtml(html));

      expect(cf.version, '0.9');
      expect(
        cf.fragment,
        '<h1>Grüße — π</h1><p>He said "hi".</p>',
        reason:
            'characters above ASCII take more than one byte each; an '
            'offset counted in characters lands inside one',
      );
      expect(cf.html, startsWith('<html>'));
      expect(cf.html, endsWith('</html>'));
      expect(cf.offsets['EndHTML'], cf.bytes.length);
    });

    test('WONEPRPD23-2: the fragment sits between its two markers', () {
      final cf = _CfHtml(tomCfHtml('<html><body><p>x</p></body></html>'));
      final bytes = cf.bytes;
      String before(int at, int n) => utf8.decode(bytes.sublist(at - n, at));
      String after(int at, int n) => utf8.decode(bytes.sublist(at, at + n));

      expect(before(cf.offsets['StartFragment']!, 20), '<!--StartFragment-->');
      expect(after(cf.offsets['EndFragment']!, 18), '<!--EndFragment-->');
      expect('<!--StartFragment-->'.allMatches(cf.html), hasLength(1));
      expect('<!--EndFragment-->'.allMatches(cf.html), hasLength(1));
    });

    test(
      'WONEPRPD23-3: the descriptor is the same length whatever it states',
      () {
        int head(String html) => _CfHtml(tomCfHtml(html)).offsets['StartHTML']!;
        final small = head('<body>x</body>');
        final large = head('<body>${'é' * 200000}</body>');
        expect(large, small);
        expect(
          _CfHtml(tomCfHtml('<body>${'é' * 200000}</body>')).fragment,
          'é' * 200000,
        );
      },
    );

    test('WONEPRPD23-4: a body tag with attributes, in any case, is found', () {
      final cf = _CfHtml(
        tomCfHtml('<HTML><BODY class="a" lang="de">ä</BODY></HTML>'),
      );
      expect(cf.fragment, 'ä');
      expect(
        cf.html,
        contains('<BODY class="a" lang="de"><!--StartFragment-->'),
      );
    });

    test('WONEPRPD23-5: a document with no body is given one', () {
      final cf = _CfHtml(tomCfHtml('<p>bare</p>'));
      expect(cf.fragment, '<p>bare</p>');
      expect(
        cf.html,
        '<html><body><!--StartFragment--><p>bare</p>'
        '<!--EndFragment--></body></html>',
      );
    });

    test('WONEPRPD23-6: an empty body is an empty fragment, not a crash', () {
      final cf = _CfHtml(tomCfHtml('<html><body></body></html>'));
      expect(cf.fragment, isEmpty);
      expect(cf.offsets['StartFragment'], cf.offsets['EndFragment']);
    });

    test('WONEPRPD23-7: the word "body" in the text is not the body tag', () {
      final cf = _CfHtml(
        tomCfHtml(
          '<html><body><p>a </body> in prose: &lt;/body&gt;</p>'
          '<p>end</p></body></html>',
        ),
      );
      // The LAST closing tag ends the body.
      expect(cf.fragment, endsWith('<p>end</p>'));
    });

    test(
      'WONEPRPD23-8: a whole printed document is the payload, unchanged',
      () {
        const html =
            '<!DOCTYPE html>\n<html>\n<head>\n<meta charset="utf-8">\n'
            '<title>T</title>\n</head>\n<body>\n<h1>T</h1>\n</body>\n</html>\n';
        final cf = _CfHtml(tomCfHtml(html));
        expect(
          cf.html
              .replaceAll('<!--StartFragment-->', '')
              .replaceAll('<!--EndFragment-->', ''),
          html,
        );
        expect(cf.fragment, '\n<h1>T</h1>\n');
      },
    );
  });

  group('WONEPRPD23 — Windows text', () {
    test('WONEPRPD23-9: every line break becomes CRLF, once', () {
      expect(tomWindowsText('a\nb\r\nc\rd'), 'a\r\nb\r\nc\r\nd');
      expect(tomWindowsText('a\r\n\r\nb'), 'a\r\n\r\nb');
      expect(tomWindowsText('no break'), 'no break');
    });
  });

  group('WONEPRPD23 — what the flow does with a runner\'s answer', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<MethodCall> runner;
    late List<MethodCall> platform;

    void answer(Object? Function(MethodCall call)? handler) {
      messenger.setMockMethodCallHandler(
        _channel,
        handler == null
            ? null
            : (call) async {
                runner.add(call);
                return handler(call);
              },
      );
    }

    setUp(() {
      runner = [];
      platform = [];
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        platform.add(call);
        return null;
      });
    });

    tearDown(() {
      answer(null);
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    Iterable<MethodCall> plainPlacements() =>
        platform.where((c) => c.method == 'Clipboard.setData');

    test(
      'WONEPRPD23-10: Linux — both, in one act, as the bytes they are',
      () async {
        answer((_) => true);
        final placed = await _place(
          html: '<p>Grüße</p>',
          text: 'Grüße\nzwei',
          platform: 'linux',
        );

        expect(placed, TomClipboardPlacement.both);
        final args = runner.single.arguments as Map;
        expect(runner.single.method, 'place');
        expect(utf8.decode(args['html'] as Uint8List), '<p>Grüße</p>');
        expect(
          args['text'],
          'Grüße\nzwei',
          reason: 'GTK writes the line endings each target asks for',
        );
        expect(
          plainPlacements(),
          isEmpty,
          reason:
              'a plain flavor placed beside it would be a second act, and '
              'a clipboard keeps only the last',
        );
      },
    );

    test('WONEPRPD23-11: Windows — both, the HTML as a CF_HTML payload and '
        'the text with CRLF', () async {
      answer((_) => true);
      final placed = await _place(
        html: '<html><body><p>Grüße</p></body></html>',
        text: 'Grüße\nzwei',
        platform: 'windows',
      );

      expect(placed, TomClipboardPlacement.both);
      final args = runner.single.arguments as Map;
      expect(_CfHtml(args['html'] as Uint8List).fragment, '<p>Grüße</p>');
      expect(args['text'], 'Grüße\r\nzwei');
      expect(plainPlacements(), isEmpty);
    });

    for (final os in ['linux', 'windows']) {
      test('WONEPRPD23-12 $os: a runner that refuses leaves the plain flavor '
          'and says one', () async {
        answer((_) => false);
        final placed = await _place(html: '<p>x</p>', text: 'x', platform: os);

        expect(placed, TomClipboardPlacement.plainTextOnly);
        expect((plainPlacements().single.arguments as Map)['text'], 'x');
      });

      test('WONEPRPD23-13 $os: a runner that raises is a refusal, not a '
          'failed copy', () async {
        answer((_) => throw PlatformException(code: 'bad-arguments'));
        final placed = await _place(html: '<p>x</p>', text: 'x', platform: os);
        expect(placed, TomClipboardPlacement.plainTextOnly);
        expect(plainPlacements(), hasLength(1));
      });

      test('WONEPRPD23-14 $os: a runner with no clipboard code is one '
          'flavor', () async {
        // No handler: the channel answers MissingPluginException.
        final placed = await _place(html: '<p>x</p>', text: 'x', platform: os);
        expect(placed, TomClipboardPlacement.plainTextOnly);
        expect(plainPlacements(), hasLength(1));
      });
    }

    test('WONEPRPD23-15: a platform with no rich clipboard never asks the '
        'runner', () async {
      answer((_) => true);
      final placed = await _place(
        html: '<p>x</p>',
        text: 'x',
        platform: 'fuchsia',
      );
      expect(placed, TomClipboardPlacement.plainTextOnly);
      expect(runner, isEmpty);
    });
  });

  group('WONEPRPC20 — the macOS program', () {
    test('WONEPRPC20-21: both flavours are in one statement', () {
      final program = tomAppleScriptClipboardProgram(
        html: '<h1>Hi</h1>',
        text: '# Hi',
      );
      // One `set the clipboard to`, because that is what makes the placement
      // atomic: a clipboard is last-writer-wins, so two statements would be two
      // placements and the second would erase the first.
      expect('set the clipboard to'.allMatches(program), hasLength(1));
      expect(program, contains('string:"# Hi"'));
      expect(program, contains('«class HTML»:«data HTML'));
    });

    test('WONEPRPC20-22: a quoted, backslashed, multi-line plain flavour '
        'survives escaping', () {
      final program = tomAppleScriptClipboardProgram(
        html: '<p>x</p>',
        text: 'He said "hi"\nC:\\path\r\nend',
      );
      // A bare quote would end the literal early and take the rest of the
      // document with it — the failure that looks like "copy only copied the
      // first line".
      expect(program, contains(r'string:"He said \"hi\"\nC:\\path\nend"'));
      expect(program, isNot(contains('\n\nend')));
    });

    test('WONEPRPC20-23: the HTML flavour is UTF-8 hex, not the system '
        'encoding', () {
      const html = '<p>Grüße — π</p>';
      final program = tomAppleScriptClipboardProgram(html: html, text: 'Grüße');
      final hex = RegExp(
        r'«data HTML([0-9a-f]+)»',
      ).firstMatch(program)!.group(1)!;
      final bytes = [
        for (var i = 0; i < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ];
      // The document declares `<meta charset="utf-8">`, so bytes in any other
      // encoding would be read back through the wrong one for every character
      // above ASCII — which is exactly the range this string is made of.
      expect(utf8.decode(bytes), html);
      expect(hex.length.isEven, isTrue);
    });
  });
}

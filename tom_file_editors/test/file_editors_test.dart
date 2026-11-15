/// The file editors over a host the test plays: the text editor names the
/// encoding and line endings it writes back; the `.env` table hides every
/// value until asked, copies through the host's protected clipboard and
/// changes one line per edit; the Markdown reader keeps front matter and
/// comments visible, keys its blocks, and reads images through its callback.
@Timeout(Duration(seconds: 120))
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_basics/utilities.dart';
import 'package:tom_file_system/tom_file_system.dart';
import 'package:tom_file_session/tom_file_session.dart';
import 'package:tom_file_editors/tom_file_editors.dart';

const String envText = '''# Database
DB_HOST=db.local
DB_PASSWORD="s3cret pass"  # rotated monthly
# OLD_PASSWORD=hunter2

# Mail
export MAIL_TOKEN=tok-123
''';

const String schemaText = '''{
  "type": "object",
  "required": ["name"],
  "properties": {
    "name": {"type": "string"},
    "port": {"type": "integer"}
  }
}''';

const String yamlText = '''# yaml-language-server: \$schema=service.schema.json
name: garden
port: eighty
paths:
  - /beds
  - /water
''';

const String questDoc = '''---
title: Garden overview
---
<!-- docspec: quest-overview/1.0 -->

# Garden Quest

The beds and the **watering**. See [the notes](notes.md) and
[watering](#watering).

![bed](img/bed.png)

## Beds

| Bed | Size |
| :-- | --: |
| South | 4 m |

## Watering

```dart
void water() => print('twice a week');
```
''';

/// A one-pixel PNG.
final Uint8List _pixel = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');

/// The host the editors talk to, recording what they ask of it.
class _Host implements TomFileEditorHost {
  _Host(this.session);

  @override
  final ForgeFileSession session;

  final List<String> notices = [];
  final List<String> copied = [];
  int undos = 0;
  int redos = 0;

  @override
  String get name => session.path.split('/').last;

  @override
  String get filePath =>
      session.fileSystem.root.resolve(session.path).toFilePath();

  @override
  Future<void> undo(BuildContext context) async {
    undos++;
    await session.undo();
  }

  @override
  Future<void> redo(BuildContext context) async {
    redos++;
    await session.redo();
  }

  @override
  void notice(BuildContext context, String message, {required String kind}) =>
      notices.add(message);

  @override
  Future<void> copyProtected(String value) async => copied.add(value);
}

late TomMemoryFileSystem _fs;

Future<_Host> _open(
  WidgetTester tester,
  String path,
  Widget Function(_Host host) editor,
) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = ForgeFileSession(fileSystem: _fs, path: path);
  await tester.runAsync(session.load);
  addTearDown(session.dispose);
  final host = _Host(session);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: StatefulBuilder(builder: (context, setState) => editor(host)),
    ),
  ));
  await _settle(tester);
  return host;
}

/// Lets futures the editors start (schema reads, image reads) complete.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
}

TextField _field(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(const Key('tom-text-source')));

/// Every string any [Text] or [EditableText] on screen draws.
Iterable<String> _screenText(WidgetTester tester) => [
      for (final t in tester.widgetList<Text>(find.byType(Text)))
        t.data ?? t.textSpan?.toPlainText() ?? '',
      for (final e in tester.widgetList<EditableText>(find.byType(EditableText)))
        e.controller.text,
    ];

void main() {
  setUp(() {
    _fs = TomMemoryFileSystem(root: Uri.directory('/work/'), seed: {
      '/work/notes/crlf.txt': 'first\r\nsecond\r\n',
      '/work/app.env': envText,
      '/work/bad.env': 'GOOD=1\nnot an entry secretword\n',
      '/work/service.yaml': yamlText,
      '/work/service.schema.json': schemaText,
      '/work/garden/overview.md': questDoc,
      '/work/garden/notes.md': '# Notes\n\nA plain note.\n',
    });
  });

  group('FILE-ED-T text', () {
    test('FILE-ED-T1: the line endings and the encoding are named as the '
        'file has them', () {
      expect(tomLineEndingsOf('a\nb\n'), 'LF');
      expect(tomLineEndingsOf('a\r\nb\r\n'), 'CRLF');
      expect(tomLineEndingsOf('a\r\nb\n'), 'Mixed LF and CRLF');
      expect(tomLineEndingsOf('a'), 'No line breaks');
      expect(tomEncodingLabel(TomTextEncoding.utf8Bom), 'UTF-8 with BOM');
    });

    testWidgets('FILE-ED-T2: the editor names the format, an edit is one '
        'splice in the session, and undo goes through the host',
        (tester) async {
      final host = await _open(tester, 'notes/crlf.txt',
          (host) => TomTextFileEditor(host: host));
      expect(tester.widget<Text>(find.byKey(const Key('tom-text-format'))).data,
          'UTF-8 · CRLF');
      expect(find.byKey(const Key('tom-text-gutter')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('tom-text-source')),
          'first\r\nsecond, edited\r\n');
      await tester.pump();
      expect(host.session.dirty, isTrue);
      expect(host.session.history.single.label, 'Edit crlf.txt');
      expect(await tester.runAsync(host.session.save),
          ForgeFileSaveOutcome.saved);
      expect(await tester.runAsync(() => _fs.readText(_fs.uriOf('notes/crlf.txt'))),
          'first\r\nsecond, edited\r\n');
    });

    testWidgets('FILE-ED-T3: a file over the read-only limit opens read-only '
        'with the reason', (tester) async {
      await tester.runAsync(() => _fs.writeText(
          _fs.uriOf('big.log'), 'x' * (forgeReadOnlyAbove + 1)));
      await _open(tester, 'big.log', (host) => TomTextFileEditor(host: host));
      expect(_field(tester).readOnly, isTrue);
      expect(find.textContaining('read-only'), findsWidgets);
    });
  });

  group('FILE-ED-E .env', () {
    testWidgets('FILE-ED-E1: the table opens with values hidden: sections as '
        'headings, active and commented-out entries told apart, no value on '
        'screen', (tester) async {
      await _open(tester, 'app.env', (host) => TomEnvFileEditor(host: host));
      expect(find.byKey(const Key('tom-env-editor')), findsOneWidget);
      expect(
          tester.widget<Switch>(find.byKey(const Key('tom-env-show-values'))).value,
          isFalse);
      expect(find.text('Database'), findsOneWidget);
      expect(
          tester
              .widget<Checkbox>(find.byKey(const Key('tom-env-active-DB_HOST')))
              .value,
          isTrue);
      expect(
          tester
              .widget<Checkbox>(
                  find.byKey(const Key('tom-env-active-OLD_PASSWORD')))
              .value,
          isFalse);
      expect(
          tester
              .widget<Text>(find.byKey(const Key('tom-env-comment-DB_PASSWORD')))
              .data,
          '# rotated monthly');
      final shown = _screenText(tester).join('\n');
      for (final secret in ['db.local', 's3cret', 'hunter2', 'tok-123']) {
        expect(shown, isNot(contains(secret)), reason: secret);
      }
    });

    testWidgets('FILE-ED-E2: Copy goes through the host\'s protected '
        'clipboard and the notice names the key only; Show reveals that one '
        'value', (tester) async {
      final host = await _open(tester, 'app.env',
          (host) => TomEnvFileEditor(host: host));
      await tester.tap(find.byKey(const Key('tom-env-hidden-DB_PASSWORD')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tom-env-copy-DB_PASSWORD')));
      await _settle(tester);
      expect(host.copied, ['s3cret pass']);
      expect(host.notices, ['Copied the value of DB_PASSWORD.']);
      expect(_screenText(tester).join('\n'), isNot(contains('s3cret')));

      await tester.tap(find.byKey(const Key('tom-env-hidden-DB_PASSWORD')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tom-env-show-DB_PASSWORD')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tom-env-value-DB_PASSWORD')), findsOneWidget);
      expect(find.byKey(const Key('tom-env-hidden-DB_HOST')), findsOneWidget,
          reason: 'Show reveals one value only');
    });

    testWidgets('FILE-ED-E3: the raw view is masked and read-only while the '
        'switch is off, and the file itself while it is on', (tester) async {
      await _open(tester, 'app.env', (host) => TomEnvFileEditor(host: host));
      await tester.tap(find.text('Raw'));
      await tester.pumpAndSettle();
      final masked = _field(tester).controller!.text;
      expect(masked, contains('DB_PASSWORD=•••  # rotated monthly'));
      expect(masked, contains('# OLD_PASSWORD=•••'));
      expect(masked, isNot(contains('s3cret')));
      expect(_field(tester).readOnly, isTrue);
      await tester.tap(find.byKey(const Key('tom-env-show-values')));
      await tester.pumpAndSettle();
      expect(_field(tester).controller!.text, envText);
    });

    testWidgets('FILE-ED-E4: toggle, add, rename and delete each change only '
        'their line, and no value reaches a history label', (tester) async {
      final host = await _open(tester, 'app.env',
          (host) => TomEnvFileEditor(host: host));
      await tester.tap(find.byKey(const Key('tom-env-active-OLD_PASSWORD')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('tom-env-delete-DB_HOST')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('tom-env-add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('tom-env-add-key')), 'NEW_KEY');
      await tester.enterText(
          find.byKey(const Key('tom-env-add-value')), 'with space');
      await tester.tap(find.byKey(const Key('tom-env-add-confirm')));
      await tester.pumpAndSettle();
      final key = find.descendant(
          of: find.byKey(const Key('tom-env-key-MAIL_TOKEN')),
          matching: find.byType(EditableText));
      await tester.enterText(key, 'MAIL_SECRET');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      final labels = host.session.history.map((e) => e.label).join('\n');
      expect(labels, isNot(contains('hunter2')));
      expect(labels, isNot(contains('with space')));
      expect(
          host.session.text,
          '# Database\n'
          'DB_PASSWORD="s3cret pass"  # rotated monthly\n'
          'OLD_PASSWORD=hunter2\n'
          '\n'
          '# Mail\n'
          'export MAIL_SECRET=tok-123\n'
          'NEW_KEY="with space"\n');
    });

    testWidgets('FILE-ED-E5: an unreadable line is reported by its number, '
        'never its text', (tester) async {
      await _open(tester, 'bad.env', (host) => TomEnvFileEditor(host: host));
      expect(tester.widget<Text>(find.byKey(const Key('tom-env-unreadable'))).data,
          'Not readable as an entry: line 2.');
      expect(_screenText(tester).join('\n'), isNot(contains('secretword')));
    });

    testWidgets('FILE-ED-E6: a key that cannot be one is refused without '
        'echoing what was typed, and the file is unchanged', (tester) async {
      final host = await _open(tester, 'app.env',
          (host) => TomEnvFileEditor(host: host));
      final key = find.descendant(
          of: find.byKey(const Key('tom-env-key-DB_HOST')),
          matching: find.byType(EditableText));
      await tester.enterText(key, 'pasted secret value');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(host.notices, isNotEmpty);
      for (final notice in host.notices) {
        expect(notice, contains('DB_HOST was kept'));
        expect(notice, isNot(contains('pasted secret value')));
      }
      expect(host.session.text, envText);
    });
  });

  group('FILE-ED-M Markdown rendering', () {
    test('FILE-ED-M1: the outline names headings by line and anchor, none '
        'from front matter or code', () {
      final outline = tomMarkdownOutline(
          '$questDoc\n```\n# not a heading\n```\nSetext\n===\n## Beds\n');
      expect(outline.map((h) => (h.level, h.text, h.slug)), [
        (1, 'Garden Quest', 'garden-quest'),
        (2, 'Beds', 'beds'),
        (2, 'Watering', 'watering'),
        (1, 'Setext', 'setext'),
        (2, 'Beds', 'beds-1'),
      ]);
      expect(outline.first.line, 5);
    });

    testWidgets('FILE-ED-M7: an image is drawn from the bytes the caller '
        'reads; one it cannot read reads as its alternative text',
        (tester) async {
      Future<void> render(String markdown) async {
        // A fresh tree per document, as a newly opened file is.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: TomMarkdownRendered(
              markdown: markdown,
              images: (src) async => src == 'img/bed.png' ? _pixel : null,
            ),
          ),
        ));
        for (var i = 0; i < 5; i++) {
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
          await tester.pump();
        }
      }

      await render('![bed](img/bed.png)\n');
      expect(find.byType(Image), findsOneWidget);
      await render('![bed](img/gone.png)\n');
      expect(find.text('[image: bed]'), findsOneWidget);
    });

    testWidgets('FILE-ED-M8: two of every keyed block render, each with its '
        'own key, and <details><summary> reads as its label', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: TomMarkdownRendered(
            markdown: '<!-- one -->\n\nBetween.\n\n<!-- two -->\n\n'
                '```dart\na();\n```\n\n```json\n{}\n```\n\n'
                '| a | b |\n|---|---|\n| 1 | 2 |\n\n| c |\n|---|\n| 3 |\n\n'
                '<details><summary>📤 result</summary>\n\nx\n\n</details>\n',
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      for (final kind in ['comment', 'code', 'table']) {
        expect(find.byKey(Key('tom-markdown-$kind-0')), findsOneWidget,
            reason: kind);
        expect(find.byKey(Key('tom-markdown-$kind-1')), findsOneWidget,
            reason: kind);
      }
      expect(find.text('📤 result'), findsOneWidget);
      expect(find.textContaining('</details>'), findsNothing);
    });

    testWidgets('FILE-ED-M9: one renderer, two styles — a file page puts a '
        'rule under a level-1 heading and scrolls; the compact body of a '
        'short text has neither, and draws its body text smaller',
        (tester) async {
      const text = '# Plan\n\nWater the **beds**.\n';
      Future<void> pump(Widget body) => tester.pumpWidget(
            MaterialApp(home: Scaffold(body: body)),
          );
      double bodySize() {
        final rich = tester.widget<Text>(find.byWidgetPredicate(
            (w) => w is Text && (w.textSpan?.toPlainText() ?? '')
                .startsWith('Water the')));
        return rich.textSpan!.style!.fontSize!;
      }

      await pump(const TomMarkdownRendered(markdown: text));
      expect(find.byType(Divider), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      final page = bodySize();

      await pump(const TomMarkdownBody(markdown: text, compact: true));
      expect(find.text('Plan'), findsOneWidget);
      expect(find.byType(Divider), findsNothing);
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(bodySize(), lessThan(page));
    });
  });
}

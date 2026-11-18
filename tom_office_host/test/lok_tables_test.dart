// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The helper's hand-kept tables against the vendored headers: the function
/// slots it checks against `nSize`, and the callback names.
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_office_host/tom_office_host.dart';

String _stripComments(String s) => s
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  final headers = '${Directory.current.path}/third_party/libreofficekit';

  test('LOK-SLOTS-1: the slots match the document class of the headers', () {
    final source = _stripComments(
      File('$headers/LibreOfficeKit.h').readAsStringSync(),
    );
    final start = source.indexOf('struct LibreOfficeKitDocumentClassStruct\n');
    expect(start, isNonNegative);
    final body = source.substring(start, source.indexOf('};', start));
    final names = RegExp(
      r'\(\s*\*\s*(\w+)\s*\)',
    ).allMatches(body).map((m) => m[1]!).toList();
    expect(names.first, 'destroy');
    expect(names.indexOf('paste'), LokDocumentSlot.paste);
    expect(names.indexOf('paintPartTile'), LokDocumentSlot.paintPartTile);
    expect(names.indexOf('paintWindow'), LokDocumentSlot.paintWindow);
    expect(names.indexOf('postWindow'), LokDocumentSlot.postWindow);
    expect(
      names.indexOf('postWindowKeyEvent'),
      LokDocumentSlot.postWindowKeyEvent,
    );
    expect(
      names.indexOf('postWindowMouseEvent'),
      LokDocumentSlot.postWindowMouseEvent,
    );
    expect(
      names.indexOf('postWindowExtTextInputEvent'),
      LokDocumentSlot.postWindowExtTextInputEvent,
    );
    expect(names.indexOf('paintWindowDPI'), LokDocumentSlot.paintWindowDPI);
  });

  test('LOK-SLOTS-2: a slot is present only inside nSize', () {
    expect(lokHasSlot(8 + 8 * 33, 32), isTrue);
    expect(lokHasSlot(8 + 8 * 32, 32), isFalse);
  });

  test('LOK-NAMES-1: the callback names match the headers', () {
    final source = _stripComments(
      File('$headers/LibreOfficeKitEnums.h').readAsStringSync(),
    );
    final fromHeader = {
      for (final m in RegExp(
        r'\bLOK_CALLBACK_([A-Z0-9_]+)\s*=\s*(\d+)',
      ).allMatches(source))
        int.parse(m[2]!): m[1]!,
    };
    expect(fromHeader.length, greaterThan(60));
    for (final MapEntry(:key, :value) in fromHeader.entries) {
      expect(LokCallbackType.names[key], value, reason: 'callback $key');
    }
    // Not in these headers; kept at upstream's number for a LibreOffice
    // that sends it.
    expect(fromHeader.containsKey(46), isFalse);
    expect(LokCallbackType.names[46], 'JSDIALOG');
    expect(LokCallbackType.window, 36);
    expect(fromHeader[LokCallbackType.window], 'WINDOW');
    expect(fromHeader[LokCallbackType.stateChanged], 'STATE_CHANGED');
    expect(fromHeader[LokCallbackType.unoCommandResult], 'UNO_COMMAND_RESULT');
    expect(fromHeader[LokCallbackType.documentPassword], 'DOCUMENT_PASSWORD');
    expect(
      fromHeader[LokCallbackType.documentPasswordToModify],
      'DOCUMENT_PASSWORD_TO_MODIFY',
    );
  });
}

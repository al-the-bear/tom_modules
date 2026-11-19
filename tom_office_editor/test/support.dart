// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_file_session/tom_file_session.dart';
import 'package:tom_file_system/tom_file_system.dart';
import 'package:tom_office_editor/testing.dart';
import 'package:tom_office_editor/tom_office_editor.dart';
import 'package:tom_office_protocol/tom_office_protocol.dart';

/// A host over an in-memory file system and a fake helper.
class TestHost implements TomOfficeEditorHost {
  TestHost({
    this.filePath = '/docs/report.docx',
    String content = 'original',
    FakeOfficeHelperLauncher? helper,
  }) : fs = TomMemoryFileSystem(seed: {filePath: content}) {
    files = TomFileSystemBinaryFiles(fs);
    this.helper = helper ?? FakeOfficeHelperLauncher(channelFor: channel);
  }

  /// A fake that writes `saved by LibreOffice` to the temporary target.
  FakeOfficeHelperChannel channel() => FakeOfficeHelperChannel(onSave: write);

  /// The fake's save: writes [savedText] to the temporary file.
  Future<bool> write(OfficeSave save) async {
    await fs.write(
      fs.uriOf(save.targetPath),
      Uint8List.fromList(utf8.encode(savedText)),
    );
    return true;
  }

  String savedText = 'saved by LibreOffice';

  final TomMemoryFileSystem fs;

  @override
  final String filePath;

  @override
  String get name => filePath.split('/').last;

  @override
  late final TomBinaryFiles files;

  @override
  late final FakeOfficeHelperLauncher helper;

  final notices = <(String, String)>[];
  final links = <String>[];
  int historyChanges = 0;

  /// The file's text on disk.
  Future<String> text() => fs.readText(fs.uriOf(filePath));

  /// Changes the file on disk, as another program would.
  Future<void> changeOnDisk(String text) =>
      fs.writeText(fs.uriOf(filePath), text);

  @override
  void notice(BuildContext context, String message, {required String kind}) =>
      notices.add((kind, message));

  @override
  void openLink(String url) => links.add(url);

  @override
  void historyChanged() => historyChanges++;

  /// What [pickImage] answers.
  String? pickedImage = '/pictures/photo.png';

  @override
  Future<String?> pickImage() async => pickedImage;
}

/// Pumps [controller]'s editor in a scaffold.
Future<void> pumpEditor(
  WidgetTester tester,
  TomOfficeEditorController controller, {
  VoidCallback? onCheckAgain,
}) async {
  tester.view.physicalSize = const Size(1000, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TomOfficeEditor(
          controller: controller,
          onCheckAgain: onCheckAgain,
        ),
      ),
    ),
  );
}

/// Lets the fake answer and tiles decode (image decoding needs real time).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  await tester.pump(const Duration(milliseconds: 200));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump();
}

/// Opens [host]'s document in a pumped editor and lets it settle.
Future<TomOfficeEditorController> openEditor(
  WidgetTester tester,
  TestHost host, {
  bool readOnly = false,
}) async {
  final controller = TomOfficeEditorController(
    host: host,
    readOnly: readOnly,
    pingInterval: const Duration(seconds: 1),
    hangTimeout: const Duration(seconds: 3),
  );
  await pumpEditor(tester, controller);
  await controller.open();
  await settle(tester);
  return controller;
}

/// Closes the editor and drops the widget, so no timer is left.
Future<void> closeEditor(
  WidgetTester tester,
  TomOfficeEditorController controller,
) async {
  await controller.close();
  await tester.pumpWidget(const SizedBox());
  controller.dispose();
  await tester.pump(const Duration(seconds: 1));
}

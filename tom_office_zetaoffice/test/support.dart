// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
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

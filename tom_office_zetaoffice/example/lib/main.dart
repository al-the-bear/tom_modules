// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// ZetaOffice in a window: pick a sample (DOCX, XLSX, PPTX), edit it in
/// ZetaOffice in the webview, save it with Cmd+S or the Save button, reopen
/// it.
///
/// - `TOM_OFFICE_FILE`: a file to open at start.
/// - `TOM_OFFICE_SAMPLES`: the sample set's `files/` (default: the tom_forge
///   quest's `office_and_pdf_integration_prototype/samples/files`). Samples
///   are copied into a scratch folder first, so the set is never written.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:tom_file_session/tom_file_session.dart';
import 'package:tom_office_editor/io.dart';
import 'package:tom_office_editor/tom_office_editor.dart';
import 'package:tom_office_zetaoffice/tom_office_zetaoffice.dart';
import 'package:tom_ui_support/tom_ui_support.dart';

void main() => runApp(const ZetaOfficeExampleApp());

/// The samples the app offers.
const kExampleSamples = [
  'report.docx',
  'letter.docx',
  'sheet.xlsx',
  'deck.pptx',
];

/// Where the sample set is.
String exampleSamplesFolder() =>
    Platform.environment['TOM_OFFICE_SAMPLES'] ??
    p.normalize(
      p.join(
        _workspaceRoot() ?? Directory.current.path,
        '_ai/quests/tom_forge/ideas/office_and_pdf_integration_prototype/'
        'samples/files',
      ),
    );

/// The workspace root above this package (holding `_ai`), when found.
String? _workspaceRoot() {
  var dir = Directory(Platform.script.toFilePath()).parent;
  for (var i = 0; i < 12; i++) {
    if (Directory(p.join(dir.path, '_ai')).existsSync()) return dir.path;
    final up = dir.parent;
    if (up.path == dir.path) break;
    dir = up;
  }
  // From the package folder (flutter run / flutter test in example/).
  dir = Directory.current;
  for (var i = 0; i < 12; i++) {
    if (Directory(p.join(dir.path, '_ai')).existsSync()) return dir.path;
    final up = dir.parent;
    if (up.path == dir.path) break;
    dir = up;
  }
  return null;
}

/// The app.
class ZetaOfficeExampleApp extends StatelessWidget {
  /// The app.
  const ZetaOfficeExampleApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(title: 'ZetaOffice', home: ZetaOfficeExamplePage());
}

/// The page: the file choice above, ZetaOffice below.
class ZetaOfficeExamplePage extends StatefulWidget {
  /// The page.
  const ZetaOfficeExamplePage({super.key});

  @override
  State<ZetaOfficeExamplePage> createState() => ZetaOfficeExamplePageState();
}

/// The page's state; the integration test drives it.
class ZetaOfficeExamplePageState extends State<ZetaOfficeExamplePage>
    with WidgetsBindingObserver {
  TomZetaOfficeController? _zeta;
  _ExampleHost? _host;
  final _scratch = Directory.systemTemp.createTempSync('zetaoffice-example-');

  /// The controller, when a file is open.
  TomZetaOfficeController? get zeta => _zeta;

  /// The open file.
  String? get filePath => _host?.filePath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final file = Platform.environment['TOM_OFFICE_FILE'];
    if (file != null && file.isNotEmpty) unawaited(openFile(file));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_zeta?.close());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Focus regained: the file may have changed meanwhile.
    if (state == AppLifecycleState.resumed) {
      unawaited(_zeta?.checkExternal());
    }
  }

  /// Opens a copy of [sample] from the sample set.
  Future<void> openSample(String sample) async {
    final copy = File(
      p.join(exampleSamplesFolder(), sample),
    ).copySync(p.join(_scratch.path, sample));
    await openFile(copy.path);
  }

  /// Opens [path] (closing the file open before).
  Future<void> openFile(String path) async {
    final old = _zeta;
    _zeta = null;
    if (old != null) {
      await old.close();
      old.dispose();
    }
    final host = _ExampleHost(
      filePath: path,
      refresh: () {
        if (mounted) setState(() {});
      },
    );
    final zeta = TomZetaOfficeController(
      host: host,
      files: TomZetaOfficeCache(),
      serving: TomZetaOfficeServer(files: host.files),
    );
    setState(() {
      _host = host;
      _zeta = zeta;
    });
    await zeta.prepare();
  }

  /// Reopens the open file.
  Future<void> reopen() async {
    final path = filePath;
    if (path != null) await openFile(path);
  }

  @override
  Widget build(BuildContext context) {
    final z = _zeta;
    void save() {
      if (z != null) unawaited(z.save());
    }

    void undo() {
      if (z != null) unawaited(z.undo());
    }

    void redo() {
      if (z != null) unawaited(z.redo());
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_host?.name ?? 'ZetaOffice'),
        actions: [
          for (final sample in kExampleSamples)
            TextButton(
              key: ValueKey('sample-$sample'),
              onPressed: () => unawaited(openSample(sample)),
              child: Text(sample),
            ),
          const VerticalDivider(),
          IconButton(
            key: const ValueKey('example-undo'),
            tooltip: 'Undo',
            onPressed: z?.canUndo ?? false ? undo : null,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            key: const ValueKey('example-redo'),
            tooltip: 'Redo',
            onPressed: z?.canRedo ?? false ? redo : null,
            icon: const Icon(Icons.redo),
          ),
          IconButton(
            key: const ValueKey('example-save'),
            tooltip: 'Save (Cmd+S)',
            onPressed: z == null ? null : save,
            icon: Icon(z?.isDirty ?? false ? Icons.save : Icons.save_outlined),
          ),
          IconButton(
            key: const ValueKey('example-reopen'),
            tooltip: 'Reopen',
            onPressed: z == null ? null : () => unawaited(reopen()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): save,
          const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): undo,
          const SingleActivator(
            LogicalKeyboardKey.keyZ,
            meta: true,
            shift: true,
          ): redo,
        },
        child: z == null
            ? const Center(child: Text('Choose a sample.'))
            : TomZetaOfficeView(key: ValueKey(z), controller: z),
      ),
    );
  }
}

/// The office editor's host, as the ZetaOffice route takes it. ZetaOffice
/// starts no helper: [helper] only answers that there is no LibreOffice.
class _ExampleHost implements TomOfficeEditorHost {
  _ExampleHost({required this.filePath, required this.refresh});

  @override
  final String filePath;

  @override
  String get name => p.basename(filePath);

  @override
  final TomBinaryFiles files = TomBinaryFileAccess();

  @override
  final TomOfficeHelperLauncher helper = const _NoHelper();

  final VoidCallback refresh;

  @override
  void notice(BuildContext context, String message, {required String kind}) =>
      tomShowNotice(
        ScaffoldMessenger.maybeOf(context),
        kind: kind,
        message: message,
      );

  @override
  void openLink(String url) {
    unawaited(Process.run('open', [url]));
  }

  @override
  void historyChanged() => refresh();

  @override
  Future<String?> pickImage() async => null;
}

/// No helper: ZetaOffice runs in the webview.
class _NoHelper implements TomOfficeHelperLauncher {
  const _NoHelper();

  @override
  LibreOfficeInstallation get installation =>
      const LibreOfficeInstallation(state: LibreOfficeState.missing);

  @override
  Future<TomOfficeHelperChannel> start({required String documentPath}) =>
      Future.error(StateError('ZetaOffice starts no helper'));
}

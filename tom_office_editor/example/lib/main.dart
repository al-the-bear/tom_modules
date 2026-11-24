// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The office editor in a window: pick a sample (DOCX, XLSX, PPTX) or a file,
/// edit it with the installed LibreOffice through the helper from the
/// binaries layer, save it with Cmd+S or the Save button, reopen it.
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
import 'package:tom_ui_support/tom_ui_support.dart';

void main() => runApp(const OfficeEditorExampleApp());

/// The samples the app offers.
const kExampleSamples = ['letter.docx', 'sheet.xlsx', 'deck.pptx'];

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
class OfficeEditorExampleApp extends StatelessWidget {
  /// The app.
  const OfficeEditorExampleApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    title: 'Office editor',
    home: OfficeEditorExamplePage(),
  );
}

/// The page: the file choice above, the editor below.
class OfficeEditorExamplePage extends StatefulWidget {
  /// The page.
  const OfficeEditorExamplePage({super.key});

  @override
  State<OfficeEditorExamplePage> createState() =>
      OfficeEditorExamplePageState();
}

/// The page's state; the integration test drives it.
class OfficeEditorExamplePageState extends State<OfficeEditorExamplePage>
    with WidgetsBindingObserver {
  LibreOfficeInstallation? _installation;
  TomOfficeEditorController? _controller;
  _ExampleHost? _host;
  final _scratch = Directory.systemTemp.createTempSync('office-example-');

  /// The editor's controller, when a file is open.
  TomOfficeEditorController? get controller => _controller;

  /// The open file.
  String? get filePath => _host?.filePath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_detect());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller?.close());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Focus regained: the file may have changed meanwhile.
    if (state == AppLifecycleState.resumed) {
      unawaited(_controller?.checkExternal());
    }
  }

  Future<void> _detect() async {
    await TomOfficeProcessLauncher.cleanUp();
    final installation = await TomLibreOfficeDetector().detect();
    if (!mounted) return;
    setState(() => _installation = installation);
    final file = Platform.environment['TOM_OFFICE_FILE'];
    if (file != null && file.isNotEmpty) await openFile(file);
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
    final old = _controller;
    _controller = null;
    if (old != null) {
      await old.close();
      old.dispose();
    }
    final installation = _installation;
    if (installation == null) return;
    final helper = TomOfficeProcessLauncher.findHelper();
    final host = _ExampleHost(
      filePath: path,
      helper: helper == null
          ? _NoHelper(installation)
          : TomOfficeProcessLauncher(
              installation: installation,
              helperExecutable: helper,
            ),
      refresh: () {
        if (mounted) setState(() {});
      },
    );
    final controller = TomOfficeEditorController(host: host);
    setState(() {
      _host = host;
      _controller = controller;
    });
    await controller.open();
  }

  /// Reopens the open file.
  Future<void> reopen() async {
    final path = filePath;
    if (path != null) await openFile(path);
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final installation = _installation;
    final canUndo = c?.canUndo ?? false;
    final canRedo = c?.canRedo ?? false;
    final dirty = c?.isDirty ?? false;
    void save() {
      if (c != null) unawaited(c.save());
    }

    void undo() => c?.undo();
    void redo() => c?.redo();
    return Scaffold(
      appBar: AppBar(
        title: Text(_host?.name ?? 'Office editor'),
        actions: [
          for (final sample in kExampleSamples)
            TextButton(
              key: ValueKey('sample-$sample'),
              onPressed: installation == null
                  ? null
                  : () => unawaited(openSample(sample)),
              child: Text(sample),
            ),
          const VerticalDivider(),
          IconButton(
            key: const ValueKey('example-undo'),
            tooltip: 'Undo',
            onPressed: canUndo ? undo : null,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            key: const ValueKey('example-redo'),
            tooltip: 'Redo',
            onPressed: canRedo ? redo : null,
            icon: const Icon(Icons.redo),
          ),
          IconButton(
            key: const ValueKey('example-save'),
            tooltip: 'Save (Cmd+S)',
            onPressed: c == null ? null : save,
            icon: Icon(dirty ? Icons.save : Icons.save_outlined),
          ),
          IconButton(
            key: const ValueKey('example-reopen'),
            tooltip: 'Reopen',
            onPressed: c == null ? null : () => unawaited(reopen()),
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
        child: installation == null
            ? const Center(child: CircularProgressIndicator())
            : c == null
            ? Center(
                child: Text(
                  installation.isUsable
                      ? 'LibreOffice ${installation.version}: choose a sample.'
                      : libreOfficeStateMessage(installation),
                ),
              )
            : TomOfficeEditor(
                key: ValueKey(c),
                controller: c,
                onCheckAgain: () => unawaited(_detect()),
              ),
      ),
    );
  }
}

class _ExampleHost implements TomOfficeEditorHost {
  _ExampleHost({
    required this.filePath,
    required this.helper,
    required this.refresh,
  });

  @override
  final String filePath;

  @override
  String get name => p.basename(filePath);

  @override
  final TomBinaryFiles files = TomBinaryFileAccess();

  @override
  final TomOfficeHelperLauncher helper;

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
  Future<String?> pickImage() async {
    // The macOS file dialog, through osascript (the example has no file
    // picker plugin).
    final result = await Process.run('osascript', [
      '-e',
      'POSIX path of (choose file of type {"public.image"} '
          'with prompt "Insert image")',
    ]);
    if (result.exitCode != 0) return null;
    final path = (result.stdout as String).trim();
    return path.isEmpty ? null : path;
  }
}

/// The launcher when the binaries layer has no helper: it fails to start.
class _NoHelper implements TomOfficeHelperLauncher {
  _NoHelper(this.installation);

  @override
  final LibreOfficeInstallation installation;

  @override
  Future<TomOfficeHelperChannel> start({required String documentPath}) =>
      Future.error(StateError('tom_office_host is not in \$TOM_BINARY_PATH'));
}

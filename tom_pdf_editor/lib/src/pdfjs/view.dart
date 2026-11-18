// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../pdf_editor_trail.dart';
import 'channel.dart';
import 'controller.dart';

/// The pdf.js view: pdf.js in the workspace's webview fork (macOS:
/// WKWebView), served by the controller's content site, in the mode the
/// host chose ([TomPdfJsController.mode]). Around it the same bars as the
/// PDFium editor (read-only, conflict, deleted), a find bar driving pdf.js's
/// search, and in `components` mode a toolbar drawn in Flutter.
class TomPdfJsView extends StatefulWidget {
  const TomPdfJsView({
    super.key,
    required this.controller,
    @visibleForTesting this.channelForTesting,
  });

  /// The controller.
  final TomPdfJsController controller;

  /// A channel instead of the webview (widget tests): no webview is built,
  /// the controller is attached to it.
  final TomPdfJsChannel? channelForTesting;

  @override
  State<TomPdfJsView> createState() => TomPdfJsViewState();
}

/// The view's state; integration tests reach the page through [evaluate].
class TomPdfJsViewState extends State<TomPdfJsView> {
  TomPdfJsController get _c => widget.controller;
  StreamSubscription<(String, String)>? _notices;
  StreamSubscription<String>? _shortcuts;
  bool _findVisible = false;
  final _findText = TextEditingController();
  final _findFocus = FocusNode(debugLabel: 'pdf.js find');
  bool _caseSensitive = false;
  bool _entireWord = false;

  @override
  void initState() {
    super.initState();
    _listen();
    final channel = widget.channelForTesting;
    if (channel != null) {
      _channel = channel;
      unawaited(_c.attach(channel));
    }
  }

  /// The webview's channel, once it exists.
  TomPdfJsChannel? _channel;

  void _listen() {
    _c.addListener(_changed);
    _notices = _c.notices.listen((n) {
      if (mounted) _c.host.notice(context, n.$2, kind: n.$1);
    });
    _shortcuts = _c.shortcuts.listen((key) {
      if (key == 'find') showFind();
    });
  }

  void _unlisten(TomPdfJsController c) {
    c.removeListener(_changed);
    unawaited(_notices?.cancel());
    unawaited(_shortcuts?.cancel());
  }

  @override
  void didUpdateWidget(TomPdfJsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _unlisten(oldWidget.controller);
      unawaited(oldWidget.controller.detach());
      _listen();
      // The webview stays; the new controller takes it over.
      final channel = widget.channelForTesting ?? _channel;
      if (channel != null) {
        _channel = channel;
        unawaited(widget.controller.attach(channel));
      }
    }
  }

  @override
  void dispose() {
    _unlisten(_c);
    _findText.dispose();
    _findFocus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Evaluates [source] in the page and answers its value: the integration
  /// tests drive pdf.js's own editors through the bridge's test hooks. Short
  /// expressions only; a test polls from Dart instead of waiting in the page.
  @visibleForTesting
  Future<Object?> evaluate(String source) async {
    final channel = _channel;
    if (channel is! _WebViewChannel) return null;
    return channel.web.evaluateJavascript(source: source);
  }

  /// Runs [body] as an async function in the page and answers its result
  /// (one promise, never a timer loop inside the page).
  @visibleForTesting
  Future<Object?> evaluateAsync(String body) async {
    final channel = _channel;
    if (channel is! _WebViewChannel) return null;
    final result = await channel.web.callAsyncJavaScript(functionBody: body);
    if (result?.error != null) throw StateError('${result!.error}');
    return result?.value;
  }

  /// Shows the find bar (the shell's Cmd+F, or Cmd+F inside the webview).
  void showFind() {
    setState(() => _findVisible = true);
    _findFocus.requestFocus();
  }

  void _find({bool again = false, bool previous = false}) => unawaited(
    _c.find(
      _findText.text,
      caseSensitive: _caseSensitive,
      entireWord: _entireWord,
      again: again,
      previous: previous,
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_c.state == TomPdfJsState.failed) return _failed(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): showFind,
      },
      child: Column(
        children: [
          if (_c.isReadOnly)
            _Bar(
              icon: Icons.lock_outline,
              text: 'Read-only.',
              actions: [
                TextButton(
                  onPressed: () => unawaited(_c.saveAsCopy()),
                  child: const Text('Save as copy'),
                ),
              ],
            ),
          if (_c.conflict != null) _conflictBar(context),
          if (_c.isDeleted && _c.conflict == null)
            const _Bar(
              icon: Icons.delete_outline,
              text: 'This file was deleted on disk. Saving recreates it.',
            ),
          if (_c.mode == TomPdfJsMode.components) _toolbar(context),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: _webview()),
                if (_c.state == TomPdfJsState.starting ||
                    _c.state == TomPdfJsState.opening)
                  const Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: LinearProgressIndicator(),
                  ),
                if (_c.state == TomPdfJsState.saving)
                  const Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: LinearProgressIndicator(),
                  ),
                if (_findVisible)
                  Positioned(top: 8, right: 16, child: _findBar(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _webview() {
    if (widget.channelForTesting != null) {
      return const ColoredBox(
        key: ValueKey('pdfjs-webview'),
        color: Color(0xFFE6E6E6),
      );
    }
    return InAppWebView(
      key: const ValueKey('pdfjs-webview'),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        isInspectable: kDebugMode,
        useShouldOverrideUrlLoading: true,
      ),
      onWebViewCreated: (web) {
        final channel = _WebViewChannel(web);
        _channel = channel;
        web.addJavaScriptHandler(
          handlerName: 'forge',
          callback: (args) {
            if (args.isNotEmpty && args.first is Map) {
              channel.receive(Map<String, Object?>.from(args.first as Map));
            }
            return null;
          },
        );
        unawaited(_c.attach(channel));
      },
      shouldOverrideUrlLoading: (web, action) async {
        final url = action.request.url;
        final site = _c.site;
        if (url == null || site == null) return NavigationActionPolicy.CANCEL;
        if (url.origin == site.baseUri.origin) {
          return NavigationActionPolicy.ALLOW;
        }
        if (url.scheme == 'http' ||
            url.scheme == 'https' ||
            url.scheme == 'mailto') {
          _c.host.openLink(url.toString());
        }
        return NavigationActionPolicy.CANCEL;
      },
      onConsoleMessage: (web, message) {
        if (message.messageLevel == ConsoleMessageLevel.ERROR) {
          pdfJsTrail('console: ${message.message}');
        }
      },
      onWebContentProcessDidTerminate: (web) => _c.contentProcessTerminated(),
    );
  }

  Widget _toolbar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = _c.state == TomPdfJsState.open && !_c.isReadOnly;
    Widget tool(int t, IconData icon, String tip, String key) => IconButton(
      key: ValueKey('pdfjs-tool-$key'),
      tooltip: tip,
      iconSize: 18,
      isSelected: _c.tool == t,
      color: _c.tool == t ? scheme.primary : null,
      icon: Icon(icon),
      onPressed: enabled || t == TomPdfJsTool.none
          ? () => unawaited(_c.setTool(t))
          : null,
    );
    return Material(
      color: scheme.surfaceContainerHighest,
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            const SizedBox(width: 8),
            Text(
              _c.pageCount == 0
                  ? ''
                  : '${_c.pageCount} ${_c.pageCount == 1 ? 'page' : 'pages'}',
            ),
            const SizedBox(width: 8),
            tool(TomPdfJsTool.none, Icons.near_me_outlined, 'Select', 'none'),
            tool(
              TomPdfJsTool.highlight,
              Icons.highlight,
              'Highlight',
              'highlight',
            ),
            tool(
              TomPdfJsTool.freeText,
              Icons.text_fields,
              'Free text',
              'freeText',
            ),
            tool(TomPdfJsTool.ink, Icons.draw_outlined, 'Ink', 'ink'),
            tool(TomPdfJsTool.stamp, Icons.image_outlined, 'Image', 'stamp'),
            const VerticalDivider(width: 16),
            IconButton(
              key: const ValueKey('pdfjs-undo'),
              tooltip: 'Undo',
              iconSize: 18,
              icon: const Icon(Icons.undo),
              onPressed: _c.canUndo ? () => unawaited(_c.undo()) : null,
            ),
            IconButton(
              key: const ValueKey('pdfjs-redo'),
              tooltip: 'Redo',
              iconSize: 18,
              icon: const Icon(Icons.redo),
              onPressed: _c.canRedo ? () => unawaited(_c.redo()) : null,
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Zoom out',
              iconSize: 18,
              icon: const Icon(Icons.zoom_out),
              onPressed: () => unawaited(_c.zoom('out')),
            ),
            IconButton(
              tooltip: 'Zoom in',
              iconSize: 18,
              icon: const Icon(Icons.zoom_in),
              onPressed: () => unawaited(_c.zoom('in')),
            ),
            TextButton(
              onPressed: () => unawaited(_c.zoom('page-width')),
              child: const Text('Fit width'),
            ),
            IconButton(
              key: const ValueKey('pdfjs-find'),
              tooltip: 'Find',
              iconSize: 18,
              icon: const Icon(Icons.search),
              onPressed: showFind,
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _findBar(BuildContext context) {
    final count = _c.findCount;
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 200,
              child: TextField(
                key: const ValueKey('pdfjs-find-field'),
                controller: _findText,
                focusNode: _findFocus,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Find in document',
                ),
                onChanged: (_) => _find(),
                onSubmitted: (_) => _find(again: true),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              count == null || _findText.text.isEmpty
                  ? ''
                  : count.total == 0
                  ? 'No matches'
                  : '${count.current} of ${count.total}',
            ),
            IconButton(
              tooltip: 'Match case',
              iconSize: 18,
              isSelected: _caseSensitive,
              icon: const Icon(Icons.text_format),
              onPressed: () {
                setState(() => _caseSensitive = !_caseSensitive);
                _find();
              },
            ),
            IconButton(
              tooltip: 'Whole word',
              iconSize: 18,
              isSelected: _entireWord,
              icon: const Icon(Icons.space_bar),
              onPressed: () {
                setState(() => _entireWord = !_entireWord);
                _find();
              },
            ),
            IconButton(
              tooltip: 'Previous',
              iconSize: 18,
              icon: const Icon(Icons.keyboard_arrow_up),
              onPressed: () => _find(again: true, previous: true),
            ),
            IconButton(
              tooltip: 'Next',
              iconSize: 18,
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: () => _find(again: true),
            ),
            IconButton(
              key: const ValueKey('pdfjs-find-close'),
              tooltip: 'Close',
              iconSize: 18,
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() => _findVisible = false);
                _findText.clear();
                unawaited(_c.find(''));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _conflictBar(BuildContext context) {
    final deleted = _c.conflict!.deleted;
    return _Bar(
      icon: Icons.warning_amber,
      text: deleted
          ? 'The file was deleted on disk since it was opened.'
          : 'The file changed on disk since it was opened.',
      actions: [
        TextButton(
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Keep mine?'),
                content: Text(
                  deleted
                      ? 'The file will be written again from this document.'
                      : 'The changes made to the file on disk will be lost.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Keep mine'),
                  ),
                ],
              ),
            );
            if (ok ?? false) await _c.keepMine();
          },
          child: const Text('Keep mine'),
        ),
        TextButton(
          onPressed: () => unawaited(_c.takeTheirs()),
          child: const Text('Take theirs'),
        ),
        TextButton(
          onPressed: () => unawaited(_c.saveAsCopy()),
          child: const Text('Save as copy'),
        ),
      ],
    );
  }

  Widget _failed(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, size: 32),
        const SizedBox(height: 8),
        Text(_c.failure ?? 'could not open', textAlign: TextAlign.center),
        if (_c.site != null) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => unawaited(_c.reload()),
            child: const Text('Reload'),
          ),
        ],
      ],
    ),
  );
}

class _Bar extends StatelessWidget {
  const _Bar({required this.icon, required this.text, this.actions = const []});

  final IconData icon;
  final String text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 18, color: scheme.onSecondaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }
}

/// The real channel: the webview's controller.
final class _WebViewChannel implements TomPdfJsChannel {
  _WebViewChannel(this.web);

  final InAppWebViewController web;
  final _messages = StreamController<Map<String, Object?>>.broadcast();

  void receive(Map<String, Object?> message) => _messages.add(message);

  @override
  Stream<Map<String, Object?>> get messages => _messages.stream;

  @override
  Future<void> load(Uri page) =>
      web.loadUrl(urlRequest: URLRequest(url: WebUri.uri(page)));

  @override
  Future<void> call(String function, [List<Object?> args = const []]) async {
    // Starts the function and returns: the page answers through messages.
    final call =
        'window.forgeBridge && window.forgeBridge.$function'
        '(${args.map(jsonEncode).join(', ')}); void 0;';
    await web.evaluateJavascript(source: call);
  }
}

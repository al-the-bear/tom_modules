// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../controller.dart' show TomOfficeNotice;
import 'controller.dart';
import 'files.dart';
import 'trail.dart';

/// ZetaOffice — LibreOffice compiled to WebAssembly, with its full
/// interface — in the webview, as the comparison route of the office
/// prototype (`part-office-webview`): the download prompt before the files
/// are cached, the start's progress (up to three minutes), the document,
/// and the reports of a failed start or a killed content process.
class TomZetaOfficeView extends StatefulWidget {
  /// The view of [controller]. [channelForTesting] stands in for the
  /// webview.
  const TomZetaOfficeView({
    super.key,
    required this.controller,
    this.channelForTesting,
  });

  /// The tab.
  final TomZetaOfficeController controller;

  /// A fake page (tests); the real one is a WKWebView.
  final TomZetaOfficeChannel? channelForTesting;

  @override
  State<TomZetaOfficeView> createState() => _TomZetaOfficeViewState();
}

class _TomZetaOfficeViewState extends State<TomZetaOfficeView> {
  StreamSubscription<TomOfficeNotice>? _notices;
  Timer? _clock;
  Timer? _heartbeat;

  TomZetaOfficeController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
    _notices = _c.notices.listen((n) {
      if (mounted) _c.host.notice(context, n.message, kind: n.kind);
    });
    // The elapsed time of the start ticks.
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _c.state == TomZetaOfficeState.starting) setState(() {});
    });
    if (kZetaOfficeDebug) {
      _heartbeat = Timer.periodic(
        const Duration(seconds: 1),
        (_) => zetaTrail('heartbeat ${_c.state.name}'),
      );
    }
    final fake = widget.channelForTesting;
    if (fake != null) unawaited(_c.attach(fake));
  }

  @override
  void didUpdateWidget(TomZetaOfficeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    // Another tab's controller in this place: follow it.
    oldWidget.controller.removeListener(_changed);
    unawaited(_notices?.cancel());
    widget.controller.addListener(_changed);
    _notices = widget.controller.notices.listen((n) {
      if (mounted) {
        widget.controller.host.notice(context, n.message, kind: n.kind);
      }
    });
    final fake = widget.channelForTesting;
    if (fake != null) unawaited(widget.controller.attach(fake));
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    unawaited(_notices?.cancel());
    _clock?.cancel();
    _heartbeat?.cancel();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  static String _mb(int bytes) => (bytes / 1e6).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final s = _c.state;
    final showsPage =
        s == TomZetaOfficeState.starting ||
        s == TomZetaOfficeState.open ||
        s == TomZetaOfficeState.saving;
    return Stack(
      children: [
        if (showsPage) Positioned.fill(child: _webview()),
        if (!showsPage)
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: _panel(context),
            ),
          ),
        if (s == TomZetaOfficeState.starting)
          Positioned.fill(child: _starting(context)),
        if (s == TomZetaOfficeState.saving)
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(key: ValueKey('zeta-saving')),
          ),
      ],
    );
  }

  Widget _panel(BuildContext context) {
    final theme = Theme.of(context);
    Widget centred(List<Widget> children) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
    switch (_c.state) {
      case TomZetaOfficeState.checking:
      case TomZetaOfficeState.closed:
        return const Center(child: CircularProgressIndicator());
      case TomZetaOfficeState.needsDownload:
        final damaged =
            _c.cacheStatus?.state == TomZetaOfficeCacheState.damaged;
        return centred([
          const Icon(Icons.cloud_download_outlined, size: 40),
          const SizedBox(height: 12),
          Text(
            'ZetaOffice runs LibreOffice in the browser engine. Its files are '
            'downloaded once from cdn.zetaoffice.net and kept on this '
            'machine: ${_mb(_c.downloadSize)} MB.',
            key: const ValueKey('zeta-download-text'),
            textAlign: TextAlign.center,
          ),
          if (damaged) ...[
            const SizedBox(height: 8),
            Text(
              'The cached files are damaged (${_c.cacheStatus?.reason}); '
              'they are downloaded again.',
              key: const ValueKey('zeta-damaged'),
              style: TextStyle(color: theme.colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('zeta-download'),
            onPressed: () => unawaited(_c.download()),
            child: Text('Download ${_mb(_c.downloadSize)} MB'),
          ),
        ]);
      case TomZetaOfficeState.downloading:
        final total = _c.downloadSize;
        return centred([
          Text(
            'Downloading ZetaOffice… ${_mb(_c.downloadReceived)} of '
            '${_mb(total)} MB',
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            key: const ValueKey('zeta-download-progress'),
            value: total <= 0 ? null : _c.downloadReceived / total,
          ),
        ]);
      case TomZetaOfficeState.busy:
        return centred([
          const Text(
            'Another ZetaOffice tab is open. ZetaOffice runs in one tab at a '
            'time: close the other one first.',
            key: ValueKey('zeta-busy'),
            textAlign: TextAlign.center,
          ),
        ]);
      case TomZetaOfficeState.processGone:
        return centred([
          const Text(
            'The system ended the web content process that showed this '
            'document. Unsaved changes are lost.',
            key: ValueKey('zeta-process-gone'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => unawaited(_c.reload()),
            child: const Text('Reopen'),
          ),
        ]);
      case TomZetaOfficeState.failed:
        return centred([
          SelectableText(
            _c.error ?? 'ZetaOffice failed.',
            key: const ValueKey('zeta-failed'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => unawaited(_c.prepare()),
            child: const Text('Try again'),
          ),
        ]);
      case TomZetaOfficeState.starting:
      case TomZetaOfficeState.open:
      case TomZetaOfficeState.saving:
        return const SizedBox.shrink();
    }
  }

  Widget _starting(BuildContext context) {
    final started = _c.startedAt;
    final seconds = started == null
        ? 0
        : DateTime.now().difference(started).inSeconds;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Starting ZetaOffice for ${_c.host.name}… $seconds s'),
              const SizedBox(height: 12),
              const LinearProgressIndicator(key: ValueKey('zeta-starting')),
              const SizedBox(height: 8),
              Text(
                _c.statusText,
                key: const ValueKey('zeta-status'),
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'The first start compiles 160 MB of WebAssembly; it can take '
                'up to three minutes.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _webview() {
    if (widget.channelForTesting != null) {
      return const ColoredBox(
        key: ValueKey('zeta-webview'),
        color: Color(0xFFE6E6E6),
      );
    }
    return InAppWebView(
      key: const ValueKey('zeta-webview'),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        isInspectable: kDebugMode,
        useShouldOverrideUrlLoading: true,
      ),
      onWebViewCreated: (web) {
        final channel = _WebViewChannel(web);
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
        final origin = _c.serving.origin;
        if (url != null && origin != null && url.origin == origin.origin) {
          return NavigationActionPolicy.ALLOW;
        }
        if (url != null && (url.scheme == 'http' || url.scheme == 'https')) {
          _c.host.openLink(url.toString());
        }
        return NavigationActionPolicy.CANCEL;
      },
      onConsoleMessage: (web, message) {
        if (message.messageLevel == ConsoleMessageLevel.ERROR) {
          zetaTrail('console: ${message.message}');
        }
      },
      onWebContentProcessDidTerminate: (web) => _c.contentProcessGone(),
    );
  }
}

class _WebViewChannel implements TomZetaOfficeChannel {
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
    final call =
        'window.forgeBridge && window.forgeBridge.$function'
        '(${args.map(jsonEncode).join(', ')}); void 0;';
    // A page that does not answer (ZetaOffice's event loop stalled) must not
    // hang the caller: the bridge's calls answer through messages anyway.
    await web
        .evaluateJavascript(source: call)
        .timeout(_callTimeout, onTimeout: () => null);
  }

  static const _callTimeout = Duration(seconds: 10);

  @override
  Future<Uint8List?> snapshot() =>
      web.takeScreenshot().timeout(_callTimeout, onTimeout: () => null);
}

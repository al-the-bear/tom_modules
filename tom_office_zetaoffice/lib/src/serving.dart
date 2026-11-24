// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:tom_file_session/io.dart';
import 'package:tom_file_session/tom_file_session.dart';

import 'files.dart';
import 'trail.dart';

/// The host page's assets in the bundle.
const kZetaOfficeAssets = 'packages/tom_office_zetaoffice/assets/zetaoffice';

/// [TomZetaOfficeServing] on `TomLocalContentServer`, every mount
/// cross-origin isolated (COOP/COEP): `host/` the page from the asset
/// bundle, `zeta/` the cache folder (`<name>.br` served with
/// `Content-Encoding: br`), `doc/<name>` the document, `save` and `copy` the
/// POST routes.
class TomZetaOfficeServer implements TomZetaOfficeServing {
  /// A server on [server] (default: the process's shared one), reading the
  /// document through [files] when it has no local path.
  TomZetaOfficeServer({
    TomLocalContentServer? server,
    AssetBundle? bundle,
    this.files,
  }) : _server = server ?? TomLocalContentServer.shared,
       _bundle = bundle ?? rootBundle;

  final TomLocalContentServer _server;
  final AssetBundle _bundle;

  /// The host's file access (a `TomBinaryFileBytes` reads remote files).
  final TomBinaryFiles? files;

  TomContentSite? _site;

  @override
  Uri? get origin => _site == null
      ? null
      : Uri(scheme: 'http', host: '127.0.0.1', port: _site!.port);

  @override
  Future<Uri> start({
    required String documentPath,
    required String name,
    required TomZetaOfficeFiles files,
    required FutureOr<void> Function(Uint8List bytes) onSave,
    required FutureOr<void> Function(Uint8List bytes) onSaveCopy,
  }) async {
    final site = await _server.openSite();
    site.onRequest = (r) => zetaTrail(
      'server: ${r.method} ${_kind(r.path)} ${r.status} (${r.bytes} bytes)',
    );
    site.mount(
      'host',
      TomContentMount.assets((path) async {
        try {
          final data = await _bundle.load('$kZetaOfficeAssets/$path');
          return data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
        } catch (_) {
          return null;
        }
      }, isolated: true),
    );
    site.mount(
      'zeta',
      // The client is WKWebView: it decodes the Brotli files although it
      // does not list br on plain HTTP.
      TomContentMount.folder(
        files.folder,
        isolated: true,
        precompressed: true,
        brotliClient: true,
      ),
    );
    final access = this.files;
    site.mount(
      'doc',
      access is TomBinaryFileBytes
          ? TomContentMount.assets(
              (_) => access.readBytes(documentPath),
              isolated: true,
            )
          : TomContentMount.file(documentPath, isolated: true),
    );
    site.mount(
      'save',
      TomContentMount.receiver(
        (content) => onSave(content.bytes),
        maxBytes: 4 << 30,
        isolated: true,
      ),
    );
    site.mount(
      'copy',
      TomContentMount.receiver(
        (content) => onSaveCopy(content.bytes),
        maxBytes: 4 << 30,
        isolated: true,
      ),
    );
    _site = site;
    final doc = site.uriOf('doc/${Uri.encodeComponent(name)}');
    return site
        .uriOf('host/index.html')
        .replace(
          queryParameters: {
            'zeta': '../zeta/',
            'doc': doc.toString(),
            'name': name,
            'save': site.uriOf('save').toString(),
            'copy': site.uriOf('copy').toString(),
          },
        );
  }

  /// A request's kind for the trail: its first segment, never the token or
  /// a file name.
  static String _kind(String path) {
    final first = path
        .split('/')
        .firstWhere((s) => s.isNotEmpty, orElse: () => '');
    if (first == 'zeta' || first == 'host') return path;
    return first;
  }

  @override
  Future<void> stop() async {
    final site = _site;
    _site = null;
    await site?.close();
  }
}

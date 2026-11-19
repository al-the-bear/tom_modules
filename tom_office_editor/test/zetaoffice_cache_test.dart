// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tom_office_editor/zetaoffice.dart';

/// A CDN on 127.0.0.1 answering as cdn.zetaoffice.net does: the three
/// soffice files Brotli-encoded (their bytes stand in here), the metadata
/// plain, a `Last-Modified`.
Future<HttpServer> _cdn(Map<String, List<int>> files, List<String> log) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final name = request.uri.pathSegments.last;
    log.add(
      '${request.method} $name ${request.headers.value('accept-encoding')}',
    );
    final body = files[name];
    final response = request.response;
    if (body == null) {
      response.statusCode = 404;
    } else {
      response.headers
        ..set('last-modified', 'Tue, 13 May 2025 09:00:00 GMT')
        ..contentLength = body.length;
      if (name != 'soffice.data.js.metadata') {
        response.headers.set('content-encoding', 'br');
      }
      if (request.method == 'GET') response.add(body);
    }
    await response.close();
  });
  return server;
}

void main() {
  late Directory dir;
  late HttpServer server;
  final log = <String>[];
  final files = {
    'soffice.js': utf8.encode('js-br'),
    'soffice.wasm': List<int>.generate(4096, (i) => i % 251),
    'soffice.data': utf8.encode('data-br'),
    'soffice.data.js.metadata': utf8.encode('{"files":[]}'),
  };

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('zeta-cache-');
    log.clear();
    server = await _cdn(files, log);
  });

  tearDown(() async {
    await server.close(force: true);
    dir.deleteSync(recursive: true);
  });

  TomZetaOfficeCache cache() => TomZetaOfficeCache(
    folder: p.join(dir.path, 'zetaoffice'),
    cdn: 'http://127.0.0.1:${server.port}/zetaoffice_latest/',
  );

  test('ZO-CACHE-1: missing, then downloaded as the CDN sends it, checked '
      'and reused', () async {
    final c = cache();
    expect((await c.status()).state, TomZetaOfficeCacheState.missing);
    final total = files.values.fold<int>(0, (a, b) => a + b.length);
    expect(await c.downloadSize(), total);
    final seen = <int>[];
    await c.download(progress: (received, all) => seen.add(received));
    expect(seen.last, total);
    // Brotli bytes kept as <name>.br; the metadata plain.
    final stored = Directory(
      c.folder,
    ).listSync().map((e) => p.basename(e.path)).toSet();
    expect(stored, {
      'soffice.js.br',
      'soffice.wasm.br',
      'soffice.data.br',
      'soffice.data.js.metadata',
      'zetaoffice.version',
    });
    expect(log.every((l) => l.endsWith(' br')), isTrue, reason: 'asked for br');
    final version =
        jsonDecode(
              File(p.join(c.folder, 'zetaoffice.version')).readAsStringSync(),
            )
            as Map;
    final wasm = (version['files'] as Map)['soffice.wasm'] as Map;
    expect(wasm['sha256'], sha256.convert(files['soffice.wasm']!).toString());
    expect(wasm['encoding'], 'br');
    expect(version['lastModified'], 'Tue, 13 May 2025 09:00:00 GMT');
    final status = await c.status();
    expect(status.state, TomZetaOfficeCacheState.ready);
    // A second open: no request at all.
    log.clear();
    expect((await cache().status()).state, TomZetaOfficeCacheState.ready);
    expect(log, isEmpty);
    await c.recordProduct('ZetaOffice 24.2.8.0.beta1');
    expect((await c.status()).version, contains('ZetaOffice 24.2.8.0.beta1'));
  });

  test('ZO-CACHE-2: a changed or missing file is damaged', () async {
    final c = cache();
    await c.download();
    File(p.join(c.folder, 'soffice.data.br')).writeAsStringSync('tampered');
    var status = await c.status();
    expect(status.state, TomZetaOfficeCacheState.damaged);
    expect(status.reason, contains('soffice.data.br'));
    await c.download();
    expect((await c.status()).state, TomZetaOfficeCacheState.ready);
    File(p.join(c.folder, 'soffice.wasm.br')).deleteSync();
    status = await c.status();
    expect(status.state, TomZetaOfficeCacheState.damaged);
    expect(status.reason, contains('missing'));
  });

  test('ZO-CACHE-3: a failed download leaves no promise of a cache', () async {
    final c = cache();
    await c.download();
    files.remove('soffice.data');
    await expectLater(c.download(), throwsA(isA<HttpException>()));
    expect((await c.status()).state, TomZetaOfficeCacheState.missing);
  });
}

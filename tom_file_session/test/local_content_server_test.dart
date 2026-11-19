@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tom_file_session/io.dart';

/// A request's answer: status, headers and body.
typedef _Answer = ({int status, HttpHeaders headers, List<int> body});

Future<_Answer> _send(
  Uri uri, {
  String method = 'GET',
  Map<String, String> headers = const {},
  List<int>? body,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, uri);
    headers.forEach(request.headers.set);
    if (body != null) request.add(body);
    final response = await request.close();
    final bytes = await response.fold<List<int>>([], (a, b) => a..addAll(b));
    return (
      status: response.statusCode,
      headers: response.headers,
      body: bytes,
    );
  } finally {
    client.close(force: true);
  }
}

void main() {
  late Directory dir;
  late TomLocalContentServer server;
  late TomContentSite site;
  final pdf = List<int>.generate(1000, (i) => i % 256);

  setUp(() async {
    dir = Directory('.dart_tool/test_scratch').absolute
      ..createSync(recursive: true);
    dir = dir.createTempSync('server-');
    Directory('${dir.path}/web').createSync();
    File('${dir.path}/web/viewer.mjs').writeAsStringSync('export {};');
    File('${dir.path}/web/app.wasm').writeAsBytesSync([0, 97, 115, 109]);
    File('${dir.path}/web/soffice.data.br').writeAsBytesSync([11, 22, 33]);
    File('${dir.path}/doc.pdf').writeAsBytesSync(pdf);
    File('${dir.path}/secret.txt').writeAsStringSync('outside');
    server = TomLocalContentServer();
    site = await server.openSite();
  });

  tearDown(() async {
    await site.close();
    dir.deleteSync(recursive: true);
  });

  group('SERVER-BASE where it listens and who it answers', () {
    test('SERVER-BASE-1: 127.0.0.1 on a free port, a 128-bit token in '
        'every path', () {
      expect(server.isRunning, isTrue);
      expect(site.baseUri.host, '127.0.0.1');
      expect(site.baseUri.port, server.port);
      expect(site.baseUri.port, isNot(0));
      expect(site.token, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(site.uriOf('doc/a b.pdf').path, '/${site.token}/doc/a%20b.pdf');
    });

    test('SERVER-BASE-2: a wrong or missing token is refused', () async {
      site.mount('doc', TomContentMount.file('${dir.path}/doc.pdf'));
      final ok = await _send(site.uriOf('doc'));
      expect(ok.status, 200);
      final wrong = site.baseUri.replace(path: '/${'0' * 32}/doc');
      expect((await _send(wrong)).status, 403);
      final none = site.baseUri.replace(path: '/doc');
      expect((await _send(none)).status, 403);
    });

    test(
      'SERVER-BASE-3: another site\'s token reaches only its own mounts',
      () async {
        final other = await server.openSite();
        other.mount('doc', TomContentMount.file('${dir.path}/doc.pdf'));
        expect(other.token, isNot(site.token));
        expect((await _send(site.uriOf('doc'))).status, 404);
        expect((await _send(other.uriOf('doc'))).status, 200);
        await other.close();
        expect((await _send(other.uriOf('doc'))).status, 403);
      },
    );

    test('SERVER-BASE-4: a foreign Host header is refused', () async {
      site.mount('doc', TomContentMount.file('${dir.path}/doc.pdf'));
      final answer = await _send(
        site.uriOf('doc'),
        headers: {'Host': 'evil.example:${server.port}'},
      );
      expect(answer.status, 403);
    });

    test('SERVER-BASE-5: the server stops when the last site closes, and '
        'starts again with the next', () async {
      final second = await server.openSite();
      await site.close();
      expect(server.isRunning, isTrue);
      await second.close();
      expect(server.isRunning, isFalse);
      expect(server.siteCount, 0);
      site = await server.openSite();
      expect(server.isRunning, isTrue);
    });
  });

  group('SERVER-MOUNT what the mounts serve', () {
    test('SERVER-MOUNT-1: a folder with MIME types by extension', () async {
      site.mount('pdfjs/web', TomContentMount.folder('${dir.path}/web'));
      final mjs = await _send(site.uriOf('pdfjs/web/viewer.mjs'));
      expect(mjs.status, 200);
      expect(mjs.headers.contentType!.mimeType, 'text/javascript');
      expect(utf8.decode(mjs.body), 'export {};');
      final wasm = await _send(site.uriOf('pdfjs/web/app.wasm'));
      expect(wasm.headers.contentType!.mimeType, 'application/wasm');
      expect((await _send(site.uriOf('pdfjs/web/nothing.js'))).status, 404);
    });

    test('SERVER-MOUNT-2: the MIME table', () {
      const expected = {
        'a.mjs': 'text/javascript; charset=utf-8',
        'a.wasm': 'application/wasm',
        'a.pdf': 'application/pdf',
        'soffice.data': 'application/octet-stream',
        'a.DOCX':
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'a.xlsx':
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'a.pptx':
            'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'a.odt': 'application/vnd.oasis.opendocument.text',
        'a.ods': 'application/vnd.oasis.opendocument.spreadsheet',
        'a.odp': 'application/vnd.oasis.opendocument.presentation',
        'noext': 'application/octet-stream',
        'dir.d/noext': 'application/octet-stream',
      };
      expected.forEach(
        (name, type) =>
            expect(TomLocalContentServer.mimeTypeOf(name), type, reason: name),
      );
    });

    test('SERVER-MOUNT-3: a path out of the folder is refused', () async {
      site.mount('web', TomContentMount.folder('${dir.path}/web'));
      for (final raw in [
        '/${site.token}/web/../secret.txt',
        '/${site.token}/web/..%2Fsecret.txt',
        '/${site.token}/web/%2E%2E/secret.txt',
      ]) {
        final socket = await Socket.connect('127.0.0.1', server.port!);
        socket.write(
          'GET $raw HTTP/1.1\r\nHost: 127.0.0.1:${server.port}\r\n'
          'Connection: close\r\n\r\n',
        );
        final text = await utf8.decoder.bind(socket).join();
        socket.destroy();
        expect(text, isNot(contains('outside')), reason: raw);
        expect(text, isNot(startsWith('HTTP/1.1 200')), reason: raw);
      }
    });

    test(
      'SERVER-MOUNT-4: a symbolic link out of the folder is refused',
      () async {
        if (Platform.isWindows) return;
        Link('${dir.path}/web/leak.txt').createSync('${dir.path}/secret.txt');
        site.mount('web', TomContentMount.folder('${dir.path}/web'));
        expect((await _send(site.uriOf('web/leak.txt'))).status, 403);
      },
    );

    test('SERVER-MOUNT-5: a file mount answers at its prefix and under any '
        'name', () async {
      site.mount('doc', TomContentMount.file('${dir.path}/doc.pdf'));
      for (final path in ['doc', 'doc/Quarterly report.pdf']) {
        final answer = await _send(site.uriOf(path));
        expect(answer.status, 200, reason: path);
        expect(answer.body, pdf);
        expect(answer.headers.contentType!.mimeType, 'application/pdf');
      }
    });

    test(
      'SERVER-MOUNT-6: an asset mount serves what its loader gives',
      () async {
        site.mount(
          'host',
          TomContentMount.assets(
            (path) async =>
                path == 'viewer.html' ? utf8.encode('<html></html>') : null,
          ),
        );
        final page = await _send(site.uriOf('host/viewer.html'));
        expect(page.status, 200);
        expect(page.headers.contentType!.mimeType, 'text/html');
        expect(utf8.decode(page.body), '<html></html>');
        expect((await _send(site.uriOf('host/other.html'))).status, 404);
      },
    );

    test('SERVER-MOUNT-7: the longest prefix wins; unmount stops it', () async {
      site.mount('a', TomContentMount.assets((p) async => utf8.encode('A:$p')));
      site.mount(
        'a/b',
        TomContentMount.assets((p) async => utf8.encode('B:$p')),
      );
      expect(
        utf8.decode((await _send(site.uriOf('a/b/x.txt'))).body),
        'B:x.txt',
      );
      expect(
        utf8.decode((await _send(site.uriOf('a/c/x.txt'))).body),
        'A:c/x.txt',
      );
      site.unmount('a/b');
      expect(
        utf8.decode((await _send(site.uriOf('a/b/x.txt'))).body),
        'A:b/x.txt',
      );
    });

    test(
      'SERVER-MOUNT-8: only GET and HEAD read; HEAD sends no body',
      () async {
        site.mount('doc', TomContentMount.file('${dir.path}/doc.pdf'));
        final head = await _send(site.uriOf('doc'), method: 'HEAD');
        expect(head.status, 200);
        expect(head.headers.contentLength, 1000);
        expect(head.body, isEmpty);
        final post = await _send(site.uriOf('doc'), method: 'POST', body: [1]);
        expect(post.status, 405);
      },
    );
  });

  group('SERVER-RANGE range requests', () {
    setUp(() => site.mount('doc', TomContentMount.file('${dir.path}/doc.pdf')));

    test('SERVER-RANGE-1: bytes=a-b gives 206 with that part', () async {
      final answer = await _send(
        site.uriOf('doc'),
        headers: {'Range': 'bytes=10-19'},
      );
      expect(answer.status, 206);
      expect(answer.headers.value('content-range'), 'bytes 10-19/1000');
      expect(answer.headers.contentLength, 10);
      expect(answer.body, pdf.sublist(10, 20));
      expect(answer.headers.value('accept-ranges'), 'bytes');
    });

    test('SERVER-RANGE-2: open-ended and suffix ranges', () async {
      final tail = await _send(
        site.uriOf('doc'),
        headers: {'Range': 'bytes=990-'},
      );
      expect(tail.status, 206);
      expect(tail.body, pdf.sublist(990));
      final suffix = await _send(
        site.uriOf('doc'),
        headers: {'Range': 'bytes=-5'},
      );
      expect(suffix.headers.value('content-range'), 'bytes 995-999/1000');
      expect(suffix.body, pdf.sublist(995));
      final past = await _send(
        site.uriOf('doc'),
        headers: {'Range': 'bytes=998-5000'},
      );
      expect(past.body, pdf.sublist(998));
    });

    test('SERVER-RANGE-3: an unsatisfiable range gives 416', () async {
      final answer = await _send(
        site.uriOf('doc'),
        headers: {'Range': 'bytes=1000-'},
      );
      expect(answer.status, 416);
      expect(answer.headers.value('content-range'), 'bytes */1000');
    });

    test('SERVER-RANGE-4: several ranges or a malformed header get the whole '
        'file', () async {
      for (final range in ['bytes=0-1,5-6', 'items=0-1', 'bytes=-']) {
        final answer = await _send(
          site.uriOf('doc'),
          headers: {'Range': range},
        );
        expect(answer.status, 200, reason: range);
        expect(answer.body, pdf, reason: range);
      }
    });

    test('SERVER-RANGE-5: an asset mount answers ranges too', () async {
      site.mount('bytes', TomContentMount.assets((_) async => pdf));
      final answer = await _send(
        site.uriOf('bytes/x.pdf'),
        headers: {'Range': 'bytes=0-3'},
      );
      expect(answer.status, 206);
      expect(answer.body, pdf.sublist(0, 4));
    });
  });

  group('SERVER-BR pre-compressed files', () {
    setUp(() {
      site.mount(
        'zeta',
        TomContentMount.folder('${dir.path}/web', precompressed: true),
      );
    });

    test('SERVER-BR-1: <name>.br is served for <name> with its encoding and '
        'the type of <name>', () async {
      final answer = await _send(
        site.uriOf('zeta/soffice.data'),
        headers: {'Accept-Encoding': 'gzip, deflate, br'},
      );
      expect(answer.status, 200);
      expect(answer.headers.value('content-encoding'), 'br');
      expect(answer.headers.contentType!.mimeType, 'application/octet-stream');
      expect(answer.headers.value('vary'), 'Accept-Encoding');
      // HttpClient does not decode br, so the body is the stored bytes.
      expect(answer.body, [11, 22, 33]);
    });

    test('SERVER-BR-2: a Range request on it gets the whole file, never a '
        'part', () async {
      final answer = await _send(
        site.uriOf('zeta/soffice.data'),
        headers: {'Accept-Encoding': 'br', 'Range': 'bytes=0-0'},
      );
      expect(answer.status, 200);
      expect(answer.headers.value('content-range'), isNull);
      expect(answer.headers.value('accept-ranges'), 'none');
      expect(answer.body, [11, 22, 33]);
    });

    test('SERVER-BR-3: a client that does not accept br gets 406', () async {
      final answer = await _send(
        site.uriOf('zeta/soffice.data'),
        headers: {'Accept-Encoding': 'gzip'},
      );
      expect(answer.status, 406);
    });

    test('SERVER-BR-5: a mount for a Brotli client (WebKit on http) gets '
        '<name>.br without listing br', () async {
      site.mount(
        'webkit',
        TomContentMount.folder(
          '${dir.path}/web',
          precompressed: true,
          brotliClient: true,
        ),
      );
      final answer = await _send(
        site.uriOf('webkit/soffice.data'),
        headers: {'Accept-Encoding': 'gzip, deflate'},
      );
      expect(answer.status, 200);
      expect(answer.headers.value('content-encoding'), 'br');
      expect(answer.body, [11, 22, 33]);
    });

    test('SERVER-BR-4: a folder mount without precompressed does not look '
        'for .br', () async {
      site.mount('plain', TomContentMount.folder('${dir.path}/web'));
      final answer = await _send(
        site.uriOf('plain/soffice.data'),
        headers: {'Accept-Encoding': 'br'},
      );
      expect(answer.status, 404);
    });
  });

  group('SERVER-HEAD headers per mount', () {
    test('SERVER-HEAD-1: an isolated mount sends COOP, COEP and CORP; another '
        'does not', () async {
      site.mount(
        'zeta',
        TomContentMount.folder('${dir.path}/web', isolated: true),
      );
      site.mount('pdfjs', TomContentMount.folder('${dir.path}/web'));
      final isolated = await _send(site.uriOf('zeta/viewer.mjs'));
      expect(
        isolated.headers.value('cross-origin-opener-policy'),
        'same-origin',
      );
      expect(
        isolated.headers.value('cross-origin-embedder-policy'),
        'require-corp',
      );
      expect(
        isolated.headers.value('cross-origin-resource-policy'),
        'same-origin',
      );
      final plain = await _send(site.uriOf('pdfjs/viewer.mjs'));
      expect(plain.headers.value('cross-origin-opener-policy'), isNull);
      expect(plain.headers.value('cross-origin-embedder-policy'), isNull);
      expect(plain.headers.value('cross-origin-resource-policy'), isNull);
      for (final answer in [isolated, plain]) {
        expect(answer.headers.value('cache-control'), 'no-store');
        expect(answer.headers.value('x-content-type-options'), 'nosniff');
      }
    });
  });

  group('SERVER-POST the receiver', () {
    test(
      'SERVER-POST-1: posted bytes reach the receiver with their name',
      () async {
        final received = <TomReceivedContent>[];
        site.mount('save', TomContentMount.receiver(received.add));
        final bytes = Uint8List.fromList(List.generate(70000, (i) => i % 251));
        final answer = await _send(
          site.uriOf('save/report.docx'),
          method: 'POST',
          headers: {'Content-Type': 'application/octet-stream'},
          body: bytes,
        );
        expect(answer.status, 200);
        expect(received.single.name, 'report.docx');
        expect(received.single.bytes, bytes);
        expect(received.single.contentType, 'application/octet-stream');
      },
    );

    test('SERVER-POST-2: a failing receiver gives 500, a large body 413, a '
        'GET 405', () async {
      site.mount(
        'fail',
        TomContentMount.receiver((_) => throw StateError('x')),
      );
      site.mount('small', TomContentMount.receiver((_) {}, maxBytes: 10));
      expect(
        (await _send(site.uriOf('fail'), method: 'POST', body: [1])).status,
        500,
      );
      expect(
        (await _send(
          site.uriOf('small'),
          method: 'POST',
          body: List.filled(11, 0),
        )).status,
        413,
      );
      expect((await _send(site.uriOf('small'))).status, 405);
    });
  });

  test(
    'SERVER-OBSERVE-1: onRequest sees every answer without the token',
    () async {
      final seen = <TomContentRequest>[];
      site.onRequest = seen.add;
      site.mount('doc', TomContentMount.file('${dir.path}/doc.pdf'));
      site.mount('save', TomContentMount.receiver((_) {}));
      await _send(site.uriOf('doc'), headers: {'Range': 'bytes=0-99'});
      await _send(site.uriOf('save'), method: 'POST', body: [1, 2, 3]);
      await _send(site.uriOf('missing'));
      expect(seen.map((r) => '$r'), [
        'GET doc 206 (100 bytes)',
        'POST save 200 (3 bytes)',
        'GET missing 404 (0 bytes)',
      ]);
      expect(seen.any((r) => r.path.contains(site.token)), isFalse);
    },
  );

  test('SERVER-SHARED-1: the shared server is one per process', () {
    expect(
      identical(TomLocalContentServer.shared, TomLocalContentServer.shared),
      isTrue,
    );
  });
}

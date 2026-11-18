import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Loads the bytes at a path relative to an asset mount, or `null` when there
/// is none — for example a Flutter host's `rootBundle.load`.
typedef TomContentLoader = Future<List<int>?> Function(String path);

/// Takes the bytes a page POSTs to a receiver mount. When it completes the
/// page gets `200`; when it throws, `500`.
typedef TomContentReceiver =
    FutureOr<void> Function(TomReceivedContent content);

/// Bytes a page sent to a receiver mount.
@immutable
final class TomReceivedContent {
  /// Received content from its parts.
  const TomReceivedContent(this.name, this.bytes, this.contentType);

  /// The path after the mount's prefix (`save/report.docx` gives
  /// `report.docx`), empty when the page posted to the prefix itself.
  final String name;

  /// The request body.
  final Uint8List bytes;

  /// The request's `Content-Type`, when it had one.
  final String? contentType;
}

/// A request a [TomContentSite] answered, as [TomContentSite.onRequest]
/// sees it.
@immutable
final class TomContentRequest {
  /// A request from its parts.
  const TomContentRequest(this.method, this.path, this.status, this.bytes);

  /// `GET`, `HEAD`, `POST`, ...
  final String method;

  /// The path below the site's token (the token is never part of it).
  final String path;

  /// The status answered.
  final int status;

  /// The bytes answered (`Content-Length`), or for a POST the bytes
  /// received; 0 when unknown.
  final int bytes;

  @override
  String toString() => '$method $path $status ($bytes bytes)';
}

/// What a [TomContentSite] serves under one path prefix.
///
/// Every mount answers with `Cache-Control: no-store` and
/// `X-Content-Type-Options: nosniff`. With [isolated] it adds the headers that
/// make a page cross-origin isolated (`SharedArrayBuffer`, as ZetaOffice
/// needs): `Cross-Origin-Opener-Policy: same-origin`,
/// `Cross-Origin-Embedder-Policy: require-corp` and
/// `Cross-Origin-Resource-Policy: same-origin`.
sealed class TomContentMount {
  const TomContentMount._(this.isolated);

  /// The files of [directory], answering `Range` requests.
  ///
  /// A path that leaves the folder (`..`, a symbolic link pointing out) is
  /// refused. With [precompressed], a missing `<name>` is served from
  /// `<name>.br` with `Content-Encoding: br` to a client that accepts it
  /// (`406` to one that does not), never as a partial answer.
  const factory TomContentMount.folder(
    String directory, {
    bool isolated,
    bool precompressed,
  }) = TomFolderMount;

  /// One file, at the prefix itself or with any name after it (so a viewer
  /// that shows the last path segment shows [name]), answering `Range`
  /// requests.
  const factory TomContentMount.file(String path, {bool isolated}) =
      TomFileMount;

  /// Bytes from [load], for assets that are not files of their own (a Flutter
  /// host's asset bundle, a page built in memory). Answers `Range` requests
  /// from the loaded bytes.
  const factory TomContentMount.assets(TomContentLoader load, {bool isolated}) =
      TomAssetMount;

  /// A POST receiver: the body goes to [receive]. [maxBytes] refuses a larger
  /// body with `413`.
  const factory TomContentMount.receiver(
    TomContentReceiver receive, {
    int maxBytes,
    bool isolated,
  }) = TomReceiverMount;

  /// Whether the cross-origin isolation headers are sent.
  final bool isolated;
}

/// [TomContentMount.folder].
final class TomFolderMount extends TomContentMount {
  /// See [TomContentMount.folder].
  const TomFolderMount(
    this.directory, {
    bool isolated = false,
    this.precompressed = false,
  }) : super._(isolated);

  /// The folder served.
  final String directory;

  /// Whether `<name>.br` stands in for a missing `<name>`.
  final bool precompressed;
}

/// [TomContentMount.file].
final class TomFileMount extends TomContentMount {
  /// See [TomContentMount.file].
  const TomFileMount(this.path, {bool isolated = false}) : super._(isolated);

  /// The file served.
  final String path;
}

/// [TomContentMount.assets].
final class TomAssetMount extends TomContentMount {
  /// See [TomContentMount.assets].
  const TomAssetMount(this.load, {bool isolated = false}) : super._(isolated);

  /// Loads an asset by its path below the prefix.
  final TomContentLoader load;
}

/// [TomContentMount.receiver].
final class TomReceiverMount extends TomContentMount {
  /// See [TomContentMount.receiver].
  const TomReceiverMount(
    this.receive, {
    this.maxBytes = 1 << 31,
    bool isolated = false,
  }) : super._(isolated);

  /// Takes the posted bytes.
  final TomContentReceiver receive;

  /// The largest body taken.
  final int maxBytes;
}

/// A local HTTP server that hands content to a webview: an `HttpServer` on
/// `127.0.0.1`, on a free port, inside the application's own process.
///
/// Each user opens a [TomContentSite] with [openSite]: a random token that
/// begins every path of the site, and the mounts registered under it. A
/// request without a known token, or for another host than `127.0.0.1` /
/// `localhost` on this port, is refused, so other local processes and pages
/// reach nothing. The server starts with the first site and stops when the
/// last one closes; [shared] is the one server of the process.
///
/// ```dart
/// final site = await TomLocalContentServer.shared.openSite();
/// site.mount('zeta', TomContentMount.folder(cache, isolated: true, precompressed: true));
/// site.mount('doc', TomContentMount.file(documentPath, isolated: true));
/// site.mount('save', TomContentMount.receiver((c) => saved.add(c.bytes)));
/// webview.load(site.uriOf('host/zeta.html'));
/// // ...
/// await site.close();
/// ```
class TomLocalContentServer {
  /// A server of its own; most hosts take [shared].
  TomLocalContentServer();

  /// The server of this process, shared by every editor that hands content
  /// to a webview.
  static final shared = TomLocalContentServer();

  /// The MIME types by lower-case extension; anything else is
  /// `application/octet-stream`.
  static const mimeTypes = <String, String>{
    'html': 'text/html; charset=utf-8',
    'htm': 'text/html; charset=utf-8',
    'js': 'text/javascript; charset=utf-8',
    'mjs': 'text/javascript; charset=utf-8',
    'css': 'text/css; charset=utf-8',
    'json': 'application/json',
    'map': 'application/json',
    'metadata': 'application/json',
    'txt': 'text/plain; charset=utf-8',
    'ftl': 'text/plain; charset=utf-8',
    'xml': 'application/xml',
    'csv': 'text/csv; charset=utf-8',
    'wasm': 'application/wasm',
    'data': 'application/octet-stream',
    'bcmap': 'application/octet-stream',
    'pfb': 'application/octet-stream',
    'icc': 'application/vnd.iccprofile',
    'pdf': 'application/pdf',
    'svg': 'image/svg+xml',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'ico': 'image/x-icon',
    'ttf': 'font/ttf',
    'otf': 'font/otf',
    'woff': 'font/woff',
    'woff2': 'font/woff2',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'pptx':
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'odt': 'application/vnd.oasis.opendocument.text',
    'ods': 'application/vnd.oasis.opendocument.spreadsheet',
    'odp': 'application/vnd.oasis.opendocument.presentation',
    'doc': 'application/msword',
    'xls': 'application/vnd.ms-excel',
    'ppt': 'application/vnd.ms-powerpoint',
    'rtf': 'application/rtf',
  };

  /// The MIME type of a file [name], by its extension.
  static String mimeTypeOf(String name) {
    final dot = name.lastIndexOf('.');
    final slash = name.lastIndexOf('/');
    if (dot <= slash + 1) return 'application/octet-stream';
    return mimeTypes[name.substring(dot + 1).toLowerCase()] ??
        'application/octet-stream';
  }

  HttpServer? _server;
  Future<HttpServer>? _starting;

  /// The bytes a receiver took, per request (for [TomContentSite.onRequest]).
  final _received = Expando<int>();
  final _sites = <String, TomContentSite>{};
  final _random = Random.secure();

  /// Whether the server is listening.
  bool get isRunning => _server != null;

  /// The port, while it runs.
  int? get port => _server?.port;

  /// The open sites.
  int get siteCount => _sites.length;

  /// Opens a site with a fresh token, starting the server if it is not
  /// running.
  Future<TomContentSite> openSite() async {
    final server = await (_server != null
        ? Future.value(_server!)
        : (_starting ??= _start()));
    final token = _newToken();
    final site = TomContentSite._(this, token, server.port);
    _sites[token] = site;
    return site;
  }

  Future<HttpServer> _start() async {
    final HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    } finally {
      _starting = null;
    }
    server.autoCompress = false;
    _server = server;
    server.listen(_handle);
    return server;
  }

  String _newToken() {
    const hex = '0123456789abcdef';
    String token;
    do {
      token = List.generate(32, (_) => hex[_random.nextInt(16)]).join();
    } while (_sites.containsKey(token));
    return token;
  }

  Future<void> _closeSite(TomContentSite site) async {
    if (_sites.remove(site.token) == null) return;
    if (_sites.isEmpty) {
      final server = _server;
      _server = null;
      await server?.close(force: true);
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      await _answer(request, response);
    } catch (_) {
      try {
        response.statusCode = HttpStatus.internalServerError;
      } on StateError {
        // Headers already sent: the connection is closed below.
      }
    } finally {
      try {
        await response.close();
      } catch (_) {
        // The client went away.
      }
    }
  }

  Future<void> _answer(HttpRequest request, HttpResponse response) async {
    final host = request.headers.host;
    final port = request.headers.port;
    if ((host != '127.0.0.1' && host != 'localhost') || port != this.port) {
      response.statusCode = HttpStatus.forbidden;
      return;
    }
    final segments = request.uri.pathSegments;
    final site = segments.isEmpty ? null : _sites[segments.first];
    if (site == null) {
      response.statusCode = HttpStatus.forbidden;
      return;
    }
    final rest = segments.skip(1).toList();
    final observer = site.onRequest;
    if (observer != null) {
      try {
        await _answerSite(request, response, site, rest);
      } finally {
        observer(
          TomContentRequest(
            request.method,
            rest.join('/'),
            response.statusCode,
            _received[request] ??
                (response.contentLength < 0 ? 0 : response.contentLength),
          ),
        );
      }
      return;
    }
    await _answerSite(request, response, site, rest);
  }

  Future<void> _answerSite(
    HttpRequest request,
    HttpResponse response,
    TomContentSite site,
    List<String> rest,
  ) async {
    if (rest.any(
      (s) => s == '..' || s == '.' || s.contains('/') || s.contains('\\'),
    )) {
      response.statusCode = HttpStatus.badRequest;
      return;
    }
    final found = site._find(rest);
    if (found == null) {
      response.statusCode = HttpStatus.notFound;
      return;
    }
    final (mount, below) = found;
    _baseHeaders(response, mount.isolated);
    if (mount is TomReceiverMount) {
      await _receive(request, response, mount, below);
      return;
    }
    if (request.method != 'GET' && request.method != 'HEAD') {
      response.statusCode = HttpStatus.methodNotAllowed;
      response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
      return;
    }
    switch (mount) {
      case TomFolderMount():
        await _serveFolder(request, response, mount, below);
      case TomFileMount():
        final file = File(mount.path);
        await _serveFile(request, response, file, file.uri.pathSegments.last);
      case TomAssetMount():
        final path = below.join('/');
        final bytes = await mount.load(path);
        if (bytes == null) {
          response.statusCode = HttpStatus.notFound;
          return;
        }
        await _serveBytes(request, response, bytes, path);
      case TomReceiverMount():
        break; // answered above
    }
  }

  static void _baseHeaders(HttpResponse response, bool isolated) {
    final headers = response.headers;
    headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    headers.set('X-Content-Type-Options', 'nosniff');
    if (isolated) {
      headers.set('Cross-Origin-Opener-Policy', 'same-origin');
      headers.set('Cross-Origin-Embedder-Policy', 'require-corp');
      headers.set('Cross-Origin-Resource-Policy', 'same-origin');
    }
  }

  Future<void> _receive(
    HttpRequest request,
    HttpResponse response,
    TomReceiverMount mount,
    List<String> below,
  ) async {
    if (request.method != 'POST' && request.method != 'PUT') {
      response.statusCode = HttpStatus.methodNotAllowed;
      response.headers.set(HttpHeaders.allowHeader, 'POST, PUT');
      return;
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      builder.add(chunk);
      if (builder.length > mount.maxBytes) {
        response.statusCode = HttpStatus.requestEntityTooLarge;
        return;
      }
    }
    _received[request] = builder.length;
    try {
      await mount.receive(
        TomReceivedContent(
          below.join('/'),
          builder.takeBytes(),
          request.headers.value(HttpHeaders.contentTypeHeader),
        ),
      );
      response.statusCode = HttpStatus.ok;
    } catch (_) {
      response.statusCode = HttpStatus.internalServerError;
    }
  }

  Future<void> _serveFolder(
    HttpRequest request,
    HttpResponse response,
    TomFolderMount mount,
    List<String> below,
  ) async {
    if (below.isEmpty) {
      response.statusCode = HttpStatus.notFound;
      return;
    }
    final root = Directory(mount.directory);
    if (!await root.exists()) {
      response.statusCode = HttpStatus.notFound;
      return;
    }
    final rootPath = await root.resolveSymbolicLinks();
    final relative = below.join(Platform.pathSeparator);
    final file = File('$rootPath${Platform.pathSeparator}$relative');
    if (await file.exists()) {
      if (!_inside(await file.resolveSymbolicLinks(), rootPath)) {
        response.statusCode = HttpStatus.forbidden;
        return;
      }
      await _serveFile(request, response, file, below.last);
      return;
    }
    final compressed = File('${file.path}.br');
    if (mount.precompressed && await compressed.exists()) {
      if (!_inside(await compressed.resolveSymbolicLinks(), rootPath)) {
        response.statusCode = HttpStatus.forbidden;
        return;
      }
      response.headers.set(HttpHeaders.varyHeader, 'Accept-Encoding');
      final accepts =
          request.headers[HttpHeaders.acceptEncodingHeader]
              ?.expand((v) => v.split(','))
              .map((v) => v.split(';').first.trim().toLowerCase())
              .contains('br') ??
          false;
      if (!accepts) {
        response.statusCode = HttpStatus.notAcceptable;
        return;
      }
      response.headers.contentType = ContentType.parse(mimeTypeOf(below.last));
      response.headers.set(HttpHeaders.contentEncodingHeader, 'br');
      // A byte range of the compressed bytes means nothing to the client, so
      // a Range header is ignored and the whole file is sent.
      response.headers.set(HttpHeaders.acceptRangesHeader, 'none');
      final length = await compressed.length();
      response.contentLength = length;
      if (request.method == 'HEAD') return;
      await response.addStream(compressed.openRead());
      return;
    }
    response.statusCode = HttpStatus.notFound;
  }

  static bool _inside(String path, String root) =>
      path == root || path.startsWith('$root${Platform.pathSeparator}');

  Future<void> _serveFile(
    HttpRequest request,
    HttpResponse response,
    File file,
    String name,
  ) async {
    if (!await file.exists()) {
      response.statusCode = HttpStatus.notFound;
      return;
    }
    final length = await file.length();
    final range = _range(request, response, length, name);
    if (range == null) return;
    final (start, end) = range;
    if (request.method == 'HEAD' || end < start) return;
    await response.addStream(file.openRead(start, end + 1));
  }

  Future<void> _serveBytes(
    HttpRequest request,
    HttpResponse response,
    List<int> bytes,
    String name,
  ) async {
    final range = _range(request, response, bytes.length, name);
    if (range == null) return;
    final (start, end) = range;
    if (request.method == 'HEAD' || end < start) return;
    response.add(bytes.sublist(start, end + 1));
  }

  /// Sets the status and the length headers for the [length]-byte content
  /// named [name], and returns the inclusive byte range to send, or `null`
  /// when the range cannot be satisfied (`416` set).
  ///
  /// One range is answered with `206`; several, or a header that does not
  /// parse, get the whole content with `200`, as HTTP allows.
  static (int, int)? _range(
    HttpRequest request,
    HttpResponse response,
    int length,
    String name,
  ) {
    final headers = response.headers;
    headers.contentType = ContentType.parse(mimeTypeOf(name));
    headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    final header = request.headers.value(HttpHeaders.rangeHeader);
    final match = header == null
        ? null
        : RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
    if (match == null || (match[1]!.isEmpty && match[2]!.isEmpty)) {
      response.contentLength = length;
      return (0, length - 1);
    }
    int start;
    int end;
    if (match[1]!.isEmpty) {
      final suffix = int.parse(match[2]!);
      start = max(0, length - suffix);
      end = length - 1;
      if (suffix == 0) start = length;
    } else {
      start = int.parse(match[1]!);
      end = match[2]!.isEmpty
          ? length - 1
          : min(int.parse(match[2]!), length - 1);
    }
    if (start >= length || start > end) {
      response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
      response.contentLength = 0;
      return null;
    }
    response.statusCode = HttpStatus.partialContent;
    headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$length');
    response.contentLength = end - start + 1;
    return (start, end);
  }
}

/// One user's part of a [TomLocalContentServer]: a token that begins every
/// path, and the mounts under it.
///
/// Paths are `http://127.0.0.1:<port>/<token>/<prefix>/<path>`. A request
/// goes to the mount with the longest prefix that matches whole segments.
final class TomContentSite {
  TomContentSite._(this._server, this.token, this.port);

  final TomLocalContentServer _server;

  /// The random token (128 bits, hexadecimal) that begins every path.
  final String token;

  /// The server's port.
  final int port;

  /// Told of every request the site answered (for a debug trail): the path
  /// below the token, never the token itself.
  void Function(TomContentRequest request)? onRequest;

  final _mounts = <String, TomContentMount>{};
  bool _closed = false;

  /// Whether [close] was called.
  bool get isClosed => _closed;

  /// The site's root, `http://127.0.0.1:<port>/<token>/`.
  Uri get baseUri => Uri.parse('http://127.0.0.1:$port/$token/');

  /// The URI of [path] below the site, e.g. `uriOf('doc/report.pdf')`.
  Uri uriOf(String path) => baseUri.resolve(
    path
        .split('/')
        .where((s) => s.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/'),
  );

  /// Serves [mount] under [prefix] (one or more path segments, `doc` or
  /// `pdfjs/web`), replacing any mount there; returns the prefix's URI.
  Uri mount(String prefix, TomContentMount mount) {
    if (_closed) throw StateError('the site is closed');
    final key = _key(prefix);
    _mounts[key] = mount;
    return uriOf(key);
  }

  /// Stops serving [prefix].
  void unmount(String prefix) => _mounts.remove(_key(prefix));

  /// Ends the site: its token is refused from now on, and the server stops
  /// when no other site is open.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _mounts.clear();
    await _server._closeSite(this);
  }

  static String _key(String prefix) {
    final segments = prefix.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty || segments.any((s) => s == '.' || s == '..')) {
      throw ArgumentError.value(prefix, 'prefix', 'not a path prefix');
    }
    return segments.join('/');
  }

  (TomContentMount, List<String>)? _find(List<String> segments) {
    for (var n = segments.length; n > 0; n--) {
      final mount = _mounts[segments.take(n).join('/')];
      if (mount != null) return (mount, segments.sublist(n));
    }
    return null;
  }
}

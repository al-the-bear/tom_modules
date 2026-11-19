// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'files.dart';
import 'trail.dart';

/// The ZetaOffice files in a folder on the machine, never in a repository:
/// fetched from [cdn] as the CDN sends them (`soffice.wasm`, `soffice.data`
/// and `soffice.js` Brotli-encoded, kept as `<name>.br` and served with
/// `Content-Encoding: br`), with `zetaoffice.version` recording the CDN's
/// `Last-Modified`, each file's size and SHA-256, and the product a document
/// reported.
class TomZetaOfficeCache implements TomZetaOfficeFiles {
  /// A cache in [folder] (default: [defaultFolder]) of the files at [cdn].
  TomZetaOfficeCache({
    String? folder,
    this.cdn = defaultCdn,
    HttpClient? client,
  }) : folder = folder ?? defaultFolder(),
       _client = client;

  /// allotropia's CDN, the latest release.
  static const defaultCdn = 'https://cdn.zetaoffice.net/zetaoffice_latest/';

  /// The four files.
  static const names = [
    'soffice.js',
    'soffice.wasm',
    'soffice.data',
    'soffice.data.js.metadata',
  ];

  /// The version file's name.
  static const versionFile = 'zetaoffice.version';

  /// `~/Library/Caches/tom_office_editor/zetaoffice` on macOS,
  /// `$XDG_CACHE_HOME` (or `~/.cache`) elsewhere, `%LOCALAPPDATA%` on
  /// Windows.
  static String defaultFolder() {
    final env = Platform.environment;
    final home = env['HOME'] ?? env['USERPROFILE'] ?? Directory.systemTemp.path;
    final String base;
    if (Platform.isMacOS) {
      base = p.join(home, 'Library', 'Caches');
    } else if (Platform.isWindows) {
      base = env['LOCALAPPDATA'] ?? p.join(home, 'AppData', 'Local');
    } else {
      base = env['XDG_CACHE_HOME'] ?? p.join(home, '.cache');
    }
    return p.join(base, 'tom_office_editor', 'zetaoffice');
  }

  @override
  final String folder;

  /// The CDN folder the files come from.
  final String cdn;

  final HttpClient? _client;

  HttpClient _http() =>
      _client ?? (HttpClient()..autoUncompress = false); // keep Brotli

  File get _version => File(p.join(folder, versionFile));

  Map<String, Object?>? _readVersion() {
    if (!_version.existsSync()) return null;
    try {
      return (jsonDecode(_version.readAsStringSync()) as Map)
          .cast<String, Object?>();
    } on FormatException {
      return null;
    }
  }

  @override
  Future<TomZetaOfficeCacheStatus> status() async {
    final version = _readVersion();
    if (version == null) {
      return const TomZetaOfficeCacheStatus(TomZetaOfficeCacheState.missing);
    }
    final files = (version['files'] as Map?)?.cast<String, Object?>() ?? {};
    final label = _label(version);
    for (final name in names) {
      final entry = (files[name] as Map?)?.cast<String, Object?>();
      if (entry == null) {
        return TomZetaOfficeCacheStatus(
          TomZetaOfficeCacheState.damaged,
          version: label,
          reason: '$name is not in $versionFile',
        );
      }
      final file = File(p.join(folder, '${entry['stored']}'));
      if (!file.existsSync()) {
        return TomZetaOfficeCacheStatus(
          TomZetaOfficeCacheState.damaged,
          version: label,
          reason: '${entry['stored']} is missing',
        );
      }
      final digest = (await sha256.bind(file.openRead()).first).toString();
      if (digest != entry['sha256']) {
        return TomZetaOfficeCacheStatus(
          TomZetaOfficeCacheState.damaged,
          version: label,
          reason: '${entry['stored']} does not match its checksum',
        );
      }
    }
    return TomZetaOfficeCacheStatus(
      TomZetaOfficeCacheState.ready,
      version: label,
    );
  }

  static String _label(Map<String, Object?> version) => [
    if (version['product'] case final String product) product,
    if (version['lastModified'] case final String lm) lm,
  ].join(', ');

  @override
  Future<int> downloadSize() async {
    final client = _http();
    try {
      var total = 0;
      for (final name in names) {
        final request = await client.headUrl(Uri.parse('$cdn$name'));
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'br');
        final response = await request.close();
        await response.drain<void>();
        if (response.contentLength <= 0) return kZetaOfficeDownloadBytes;
        total += response.contentLength;
      }
      return total;
    } catch (e) {
      zetaTrail('download size: $e');
      return kZetaOfficeDownloadBytes;
    } finally {
      if (_client == null) client.close();
    }
  }

  @override
  Future<void> download({
    void Function(int received, int total)? progress,
  }) async {
    final client = _http();
    final dir = Directory(folder)..createSync(recursive: true);
    final total = await downloadSize();
    var received = 0;
    final entries = <String, Object?>{};
    String? lastModified;
    try {
      // The old version file goes first: a broken download leaves no
      // promise of a complete cache.
      if (_version.existsSync()) _version.deleteSync();
      for (final name in names) {
        final request = await client.getUrl(Uri.parse('$cdn$name'));
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'br');
        final response = await request.close();
        if (response.statusCode != 200) {
          await response.drain<void>();
          throw HttpException(
            '$name answered ${response.statusCode}',
            uri: Uri.parse('$cdn$name'),
          );
        }
        final encoding = response.headers.value(
          HttpHeaders.contentEncodingHeader,
        );
        final brotli = encoding == 'br';
        if (encoding != null && !brotli && encoding != 'identity') {
          throw HttpException('$name came $encoding-encoded');
        }
        lastModified ??= response.headers.value(HttpHeaders.lastModifiedHeader);
        final stored = brotli ? '$name.br' : name;
        final temporary = File(p.join(dir.path, '.$stored.part'));
        final sink = temporary.openWrite();
        final hash = AccumulatorSink<Digest>();
        final hasher = sha256.startChunkedConversion(hash);
        var size = 0;
        await for (final chunk in response) {
          sink.add(chunk);
          hasher.add(chunk);
          size += chunk.length;
          received += chunk.length;
          progress?.call(received, total);
        }
        await sink.close();
        hasher.close();
        // The other form of the file, from an older download, goes.
        for (final other in [name, '$name.br']) {
          final f = File(p.join(dir.path, other));
          if (other != stored && f.existsSync()) f.deleteSync();
        }
        temporary.renameSync(p.join(dir.path, stored));
        entries[name] = {
          'stored': stored,
          'encoding': brotli ? 'br' : 'identity',
          'size': size,
          'sha256': hash.events.single.toString(),
        };
        zetaTrail('downloaded $name: $size bytes${brotli ? ' (br)' : ''}');
      }
      _version.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'source': cdn,
          'lastModified': lastModified,
          'downloaded': DateTime.now().toUtc().toIso8601String(),
          'files': entries,
        }),
      );
    } finally {
      if (_client == null) client.close();
    }
  }

  @override
  Future<void> recordProduct(String product) async {
    final version = _readVersion();
    if (version == null || version['product'] == product) return;
    version['product'] = product;
    _version.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(version),
    );
  }
}

/// A sink that keeps what is added (the chunked SHA-256's digest).
class AccumulatorSink<T> implements Sink<T> {
  /// What was added.
  final events = <T>[];

  @override
  void add(T event) => events.add(event);

  @override
  void close() {}
}

/// Bytes as a `Uint8List` (the receiver's body).
Uint8List asBytes(List<int> data) =>
    data is Uint8List ? data : Uint8List.fromList(data);

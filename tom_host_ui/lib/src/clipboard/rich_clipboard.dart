/// The desktop answer to "copy with formatting": HTML and plain text on the
/// system clipboard together.
///
/// Flutter's own `Clipboard` carries plain text and nothing else, so the rich
/// flavour has to come from the platform. A clipboard is last-writer-wins, so
/// both flavours go over in **one act** on every platform:
///
/// * **macOS** — one AppleScript statement setting `string:` and
///   `«class HTML»` together, run by `osascript`.
/// * **Linux** — the host application's runner, which is already a GTK
///   application, takes the ownership itself and offers `text/html` and the
///   plain-text targets.
/// * **Windows** — the runner, which is already a Win32 window, opens the
///   clipboard once and sets `CF_UNICODETEXT` and `HTML Format`.
///
/// The Linux and Windows halves are **native code the host application
/// provides** in its runner, answering [TomRichClipboard.channel] — see the
/// README, "What a host application provides". A host whose runner does not
/// answer gets [TomClipboardPlacement.plainTextOnly], said as such. What can
/// be *wrong* is built here, as pure functions over two strings, and tested
/// without a clipboard — the AppleScript program, the CF_HTML payload with
/// its byte offsets, the Windows line endings.
///
/// A platform that refuses leaves the plain flavour and says so
/// ([TomClipboardPlacement.plainTextOnly]); it never claims both.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'clipboard_placement.dart';

/// Places both flavours on the clipboard of a desktop host.
class TomRichClipboard {
  /// The channel the host's Linux and Windows runners answer, with one method,
  /// `place`, taking `html` and `text` and answering a bool.
  final MethodChannel channel;

  /// `Platform.operatingSystem` unless a test says otherwise.
  final String? platform;

  const TomRichClipboard({required this.channel, this.platform});

  /// Places both flavours, returning what the platform actually accepted.
  /// A [TomPlaceOnClipboard].
  Future<TomClipboardPlacement> place({
    required String html,
    required String text,
  }) async {
    final os = platform ?? Platform.operatingSystem;

    if (os == 'linux' || os == 'windows') {
      // The runner places both in one act, so nothing is placed before it: a
      // plain flavour put down first would be a second act, and the one that
      // lost.
      if (await _placeThroughRunner(os: os, html: html, text: text)) {
        return TomClipboardPlacement.both;
      }
      return await _placePlain(text)
          ? TomClipboardPlacement.plainTextOnly
          : TomClipboardPlacement.failed;
    }

    // The plain flavour first and unconditionally, so that every path below —
    // including the ones that fail — leaves the clipboard holding something
    // the user can paste. On macOS the AppleScript below replaces the whole
    // pasteboard with *both* flavours, so this is not a partial write it has
    // to undo; it is the floor.
    if (!await _placePlain(text)) return TomClipboardPlacement.failed;
    if (os != 'macos') return TomClipboardPlacement.plainTextOnly;
    return await _placeOnMacOS(html: html, text: text)
        ? TomClipboardPlacement.both
        : TomClipboardPlacement.plainTextOnly;
  }

  /// Asks the runner to place both. False for a runner that refused, that
  /// raised, or that is not there — a build whose runner carries no clipboard
  /// code answers [MissingPluginException], and that is "one flavour", not a
  /// failed copy.
  Future<bool> _placeThroughRunner({
    required String os,
    required String html,
    required String text,
  }) async {
    try {
      final placed = await channel.invokeMethod<bool>('place', {
        'html': os == 'windows'
            ? tomCfHtml(html)
            : Uint8List.fromList(utf8.encode(html)),
        'text': os == 'windows' ? tomWindowsText(text) : text,
      });
      return placed ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

Future<bool> _placePlain(String text) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  } on PlatformException {
    return false;
  }
}

/// [text] with Windows line endings: every line break becomes `\r\n`.
///
/// A Windows text target that is handed a bare `\n` shows one long line in
/// the programs that still care, Notepad among them.
String tomWindowsText(String text) => text
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .replaceAll('\n', '\r\n');

const String _startFragment = '<!--StartFragment-->';
const String _endFragment = '<!--EndFragment-->';

/// The Windows `HTML Format` payload for [html]: the CF_HTML descriptor, then
/// the document with its fragment marked.
///
/// The descriptor's four numbers are **byte** offsets into this same payload,
/// UTF-8 encoded, counted from its first byte. They are written ten digits
/// wide, so the descriptor's own length does not depend on the values it
/// states — which is what lets them be computed in one pass.
///
/// The fragment is the content of `<body>`. A document with no `<body>` is
/// wrapped in one, so there is always a fragment and it is always inside a
/// document.
Uint8List tomCfHtml(String html) {
  final open = RegExp(r'<body\b[^>]*>', caseSensitive: false).firstMatch(html);
  final close = html.toLowerCase().lastIndexOf('</body>');
  final String document;
  if (open == null || close < open.end) {
    document = '<html><body>$_startFragment$html$_endFragment</body></html>';
  } else {
    document =
        '${html.substring(0, open.end)}$_startFragment'
        '${html.substring(open.end, close)}$_endFragment'
        '${html.substring(close)}';
  }

  String descriptor(int startHtml, int endHtml, int startFrag, int endFrag) {
    String n(int v) => v.toString().padLeft(10, '0');
    return 'Version:0.9\r\n'
        'StartHTML:${n(startHtml)}\r\n'
        'EndHTML:${n(endHtml)}\r\n'
        'StartFragment:${n(startFrag)}\r\n'
        'EndFragment:${n(endFrag)}\r\n';
  }

  final body = utf8.encode(document);
  final head = utf8.encode(descriptor(0, 0, 0, 0)).length;
  final marker = document.indexOf(_startFragment) + _startFragment.length;
  final startFragment =
      head + utf8.encode(document.substring(0, marker)).length;
  final endFragment =
      head +
      utf8
          .encode(document.substring(0, document.lastIndexOf(_endFragment)))
          .length;

  return Uint8List.fromList([
    ...utf8.encode(
      descriptor(head, head + body.length, startFragment, endFragment),
    ),
    ...body,
  ]);
}

/// `set the clipboard to {string:…, «class HTML»:«data HTML<hex>»}` — the one
/// AppleScript form that sets two pasteboard flavours in a single act, which is
/// what the clipboard's last-writer-wins rule requires.
///
/// Written to a file rather than passed with `-e`: a script argument goes
/// through `ARG_MAX`, and the hex encoding doubles an HTML document that was
/// already the size of a chapter.
Future<bool> _placeOnMacOS({required String html, required String text}) async {
  Directory? scratch;
  try {
    scratch = await Directory.systemTemp.createTemp('tom_clip_');
    final script = File('${scratch.path}/clip.applescript');
    await script.writeAsString(
      tomAppleScriptClipboardProgram(html: html, text: text),
    );
    final result = await Process.run('osascript', [script.path]);
    return result.exitCode == 0;
  } on ProcessException {
    // No `osascript` — a stripped image, or a sandbox that withholds it. The
    // plain flavour is already placed, so the honest answer is "one flavour",
    // not "the copy failed".
    return false;
  } on FileSystemException {
    return false;
  } finally {
    // Best effort: a leftover temp directory is litter, not a failure, and
    // deleting it must not turn a successful copy into a reported one.
    try {
      await scratch?.delete(recursive: true);
    } on FileSystemException {
      // ignored — see above.
    }
  }
}

/// The AppleScript that places both flavours — built separately from the
/// process that runs it, because this is the part that can be *wrong*.
///
/// Escaping and hex encoding are testable; a pasteboard is not, at least not
/// without clobbering the clipboard of whoever is running the suite, which is
/// a real cost to pay for a weaker assertion than this one.
String tomAppleScriptClipboardProgram({
  required String html,
  required String text,
}) =>
    'set the clipboard to {string:"${_appleScriptString(text)}", '
    '«class HTML»:«data HTML${_hex(html)}»}\n';

/// Escapes [value] for an AppleScript string literal.
///
/// Backslash first, or the escape character introduced by the second rule
/// would be escaped by the first on a later pass.
String _appleScriptString(String value) => value
    .replaceAll(r'\', r'\\')
    .replaceAll('"', r'\"')
    .replaceAll('\r\n', r'\n')
    .replaceAll('\n', r'\n')
    .replaceAll('\r', r'\n');

/// UTF-8 bytes of [value] as lowercase hex — the payload form of an
/// AppleScript `«data …»` literal.
///
/// UTF-8 explicitly, not the system encoding: the document declares
/// `<meta charset="utf-8">`, so bytes in any other encoding would be read
/// back through the wrong one for every character above ASCII.
String _hex(String value) {
  final buffer = StringBuffer();
  for (final byte in utf8.encode(value)) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:async';
import 'dart:typed_data';

import 'package:tom_office_protocol/tom_office_protocol.dart';

import '../detection/installation.dart';
import '../helper/helper_channel.dart';

/// A helper channel without LibreOffice: it answers `hello` at once, `open`
/// with [opened] (or a password question), every `renderTile` with a tile
/// of one colour, `save` through [onSave], `copy` with [clipboard], `ping`
/// with `pong`; [callback] and [emit] script what LibreOffice would send.
/// Every command sent is kept in [sent].
class FakeOfficeHelperChannel implements TomOfficeHelperChannel {
  /// A fake. [password] makes `open` ask for it ([passwordToModify]: a
  /// password to modify) until it is given.
  FakeOfficeHelperChannel({
    this.opened = const OfficeOpened(
      docType: OfficeDocType.text,
      parts: 1,
      partNames: ['Page 1'],
      currentPart: 0,
      width: 12240,
      height: 15840,
      tileMode: OfficePixelFormat.bgra,
    ),
    this.password,
    this.passwordToModify = false,
    this.tileColour = const [0x40, 0x80, 0xC0, 0xFF],
    this.onSave,
    this.clipboard = const {'text/plain;charset=utf-8': 'copied'},
    this.answerPings = true,
    this.answerTiles = true,
    this.values = const {},
    this.jsonDialogs = false,
    this.windowColour = const [0xF0, 0xF0, 0xF0, 0xFF],
  }) {
    // `hello` goes to the first listener, as a real helper's stdout waits
    // for its reader.
    _events = StreamController<OfficeHelperEvent>.broadcast(
      onListen: () {
        if (_helloSent) return;
        _helloSent = true;
        scheduleMicrotask(
          () => emit(
            const OfficeHello(
              protocol: kOfficeProtocolVersion,
              helperVersion: 'fake',
              lokVersion: 'fake',
              pid: 4242,
            ),
          ),
        );
      },
    );
  }

  bool _helloSent = false;

  /// What `open` answers.
  final OfficeOpened opened;

  /// The document's password, or `null` for none.
  final String? password;

  /// Whether [password] is a password to modify.
  final bool passwordToModify;

  /// One tile pixel, in the tile's format.
  final List<int> tileColour;

  /// Answers `save`: whether it was written (the test writes the temporary
  /// file itself). `null` answers ok.
  final FutureOr<bool> Function(OfficeSave save)? onSave;

  /// What `copy` answers.
  final Map<String, String> clipboard;

  /// Whether `ping` is answered (false: the helper hangs).
  final bool answerPings;

  /// Whether tiles are answered.
  final bool answerTiles;

  /// What `getCommandValues` answers, by command (`{}` for others).
  final Map<String, String> values;

  /// Whether `dialogMode json` is taken (false: refused as LibreOffice's
  /// desktop build does, `jsonDialogsUnavailable`).
  final bool jsonDialogs;

  /// One pixel of a painted window.
  final List<int> windowColour;

  /// Every command sent, in order.
  final List<OfficeHelperCommand> sent = [];

  late final StreamController<OfficeHelperEvent> _events;
  final _log = StreamController<String>.broadcast();
  final _exit = Completer<TomOfficeHelperExit>();
  bool _passwordGiven = false;

  /// The commands of type [T] sent.
  List<T> sentOf<T extends OfficeHelperCommand>() =>
      sent.whereType<T>().toList();

  @override
  Stream<OfficeHelperEvent> get events => _events.stream;

  @override
  Stream<String> get log => _log.stream;

  @override
  Future<TomOfficeHelperExit> get exit => _exit.future;

  /// Sends [event] as the helper would.
  void emit(OfficeHelperEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  /// Sends a LibreOfficeKit callback.
  void callback(String type, String payload) =>
      emit(OfficeCallback(type: type, payload: payload));

  /// Ends the helper as a crash would.
  void crash({int code = -11, String stderr = 'Segmentation fault'}) => _end(
    TomOfficeHelperExit(
      code: code,
      reason: 'signal ${-code}',
      stderrTail: stderr,
    ),
  );

  void _end(TomOfficeHelperExit exit) {
    if (_exit.isCompleted) return;
    _exit.complete(exit);
    unawaited(_events.close());
    unawaited(_log.close());
  }

  @override
  void send(OfficeHelperCommand command) {
    if (_exit.isCompleted) return;
    sent.add(command);
    switch (command) {
      case OfficeOpen():
        if (password != null && !passwordToModify) {
          emit(const OfficePasswordNeeded(toModify: false));
          return;
        }
        if (password != null && passwordToModify) {
          emit(const OfficePasswordNeeded(toModify: true));
          return;
        }
        emit(opened);
      case OfficePassword(password: final given):
        if (given == null) {
          if (passwordToModify) {
            emit(_openedReadOnly);
          } else {
            emit(
              const OfficeError(
                code: 'passwordCancelled',
                message: 'the password was cancelled',
              ),
            );
          }
          return;
        }
        if (given == password) {
          _passwordGiven = true;
          emit(opened);
        } else {
          emit(OfficePasswordNeeded(toModify: passwordToModify));
        }
      case OfficeRenderTile(
        :final id,
        :final part,
        :final x,
        :final y,
        :final w,
        :final h,
        :final pxW,
        :final pxH,
      ):
        if (!answerTiles) return;
        final pixels = Uint8List(pxW * pxH * 4);
        for (var i = 0; i < pixels.length; i += 4) {
          pixels.setRange(i, i + 4, tileColour);
        }
        emit(
          OfficeTile(
            id: id,
            part: part,
            x: x,
            y: y,
            w: w,
            h: h,
            pxW: pxW,
            pxH: pxH,
            format: opened.tileMode,
            pixels: pixels,
          ),
        );
      case OfficeSave(:final id):
        unawaited(() async {
          final ok = await (onSave?.call(command) ?? true);
          emit(OfficeSaved(id: id, ok: ok, error: ok ? null : 'save failed'));
        }());
      case OfficeCopy(:final id):
        emit(OfficeClipboard(id: id, data: clipboard));
      case OfficeCommandValues(:final id, :final command):
        emit(OfficeValues(id: id, json: values[command] ?? '{}'));
      case OfficePaintWindow(
        :final id,
        :final windowId,
        :final x,
        :final y,
        :final w,
        :final h,
      ):
        final pixels = Uint8List(w * h * 4);
        for (var i = 0; i < pixels.length; i += 4) {
          pixels.setRange(i, i + 4, windowColour);
        }
        emit(
          OfficeWindowPixels(
            id: id,
            windowId: windowId,
            x: x,
            y: y,
            w: w,
            h: h,
            format: opened.tileMode,
            pixels: pixels,
          ),
        );
      case OfficeWindowClose(:final windowId):
        emit(OfficeWindowChanged(windowId: windowId, action: 'close'));
      case OfficeDialogModeMessage(:final mode):
        if (mode == OfficeDialogMode.json && !jsonDialogs) {
          emit(
            const OfficeError(
              code: 'jsonDialogsUnavailable',
              message: 'this LibreOffice has no JSON dialogs',
            ),
          );
        }
      case OfficePing(:final id):
        if (answerPings) emit(OfficePong(id: id));
      case OfficeClose():
        emit(const OfficeClosed());
        _end(const TomOfficeHelperExit(code: 0, reason: 'exit 0'));
      default:
        break;
    }
  }

  OfficeOpened get _openedReadOnly => OfficeOpened(
    docType: opened.docType,
    parts: opened.parts,
    partNames: opened.partNames,
    currentPart: opened.currentPart,
    width: opened.width,
    height: opened.height,
    tileMode: opened.tileMode,
    readOnly: true,
  );

  /// Whether the right password was given.
  bool get passwordGiven => _passwordGiven;

  @override
  Future<TomOfficeHelperExit> close() async {
    send(const OfficeClose());
    return exit;
  }

  @override
  void kill() => _end(
    const TomOfficeHelperExit(code: -9, reason: 'signal 9', stderrTail: ''),
  );
}

/// A launcher that hands out fake channels ([channelFor] makes each; one
/// default fake when `null`), for [installation].
class FakeOfficeHelperLauncher implements TomOfficeHelperLauncher {
  /// A launcher.
  FakeOfficeHelperLauncher({
    this.installation = const LibreOfficeInstallation(
      state: LibreOfficeState.found,
      bundlePath: '/Applications/LibreOffice.app',
      version: kLibreOfficeMinimumVersion,
    ),
    FakeOfficeHelperChannel Function()? channelFor,
  }) : _make = channelFor ?? FakeOfficeHelperChannel.new;

  @override
  final LibreOfficeInstallation installation;

  final FakeOfficeHelperChannel Function() _make;

  /// Every channel started, in order.
  final List<FakeOfficeHelperChannel> channels = [];

  /// The documents the helpers were started for.
  final List<String> documents = [];

  /// The last channel started.
  FakeOfficeHelperChannel get last => channels.last;

  @override
  Future<TomOfficeHelperChannel> start({required String documentPath}) async {
    documents.add(documentPath);
    final channel = _make();
    channels.add(channel);
    return channel;
  }
}

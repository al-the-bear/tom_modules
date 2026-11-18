// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// A fake LibreOfficeKit for the host's unit tests: it records every call and
/// plays the password, window and command behaviour the tests script.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:tom_office_host/tom_office_host.dart';

class FakeRuntime implements LokRuntime {
  final _callbacks = StreamController<LokCallback>.broadcast(sync: true);
  final calls = <String>[];
  bool initFails = false;
  FakeOffice? office;

  /// The password the document needs to open, and to modify.
  String? openPassword;
  String? modifyPassword;
  int _asked = 0;

  @override
  Stream<LokCallback> get callbacks => _callbacks.stream;

  void emit(int type, String payload) =>
      _callbacks.add(LokCallback(type, payload));

  @override
  int get passwordAsked => _asked;

  @override
  LokOffice? init(String program, String profileUrl) {
    calls.add('init $program $profileUrl');
    if (initFails) return null;
    return office = FakeOffice(this);
  }
}

class FakeOffice implements LokOffice {
  FakeOffice(this.runtime);

  final FakeRuntime runtime;
  String? _armed;
  bool _isArmed = false;
  int features = 0;
  final loads = <String>[];
  FakeDocument? document;
  bool destroyed = false;
  String? loadError;

  /// The next document opens read-only (as with a stale lock file).
  bool forceReadOnly = false;

  /// Every armed answer, kept to show the test what was given (the host
  /// itself must never log it).
  final armed = <String?>[];

  @override
  String get versionInfo => '{"ProductName":"Fake","ProductVersion":"0"}';

  @override
  void setOptionalFeatures(int features) => this.features = features;

  @override
  void armPasswordAnswer(String? password) {
    _armed = password;
    _isArmed = true;
    armed.add(password);
    runtime._asked = 0;
  }

  /// What LibreOffice does when it asks: the armed answer once, then null.
  String? _ask(int kind) {
    final answer = _isArmed ? _armed : null;
    runtime._asked |= _isArmed ? kind : kind | 4;
    _isArmed = false;
    return answer;
  }

  @override
  LokDocument? load(String path, String optionsJson) {
    loads.add('$path $optionsJson');
    if (loadError != null) return null;
    if (runtime.openPassword != null && _ask(1) != runtime.openPassword) {
      return null;
    }
    var readOnly = forceReadOnly;
    if (runtime.modifyPassword != null) {
      final given = _ask(2);
      if (given != runtime.modifyPassword) {
        // Asked again after a wrong answer, then read-only.
        if (given != null) {
          _ask(2);
        }
        readOnly = true;
      }
    }
    return document = FakeDocument(runtime, readOnly: readOnly);
  }

  @override
  String? lastError() => loadError ?? 'wrong password';

  @override
  void destroy() => destroyed = true;
}

class FakeDocument implements LokDocument {
  FakeDocument(this.runtime, {this.readOnly = false});

  final FakeRuntime runtime;
  final bool readOnly;
  final calls = <String>[];
  bool destroyed = false;
  int _part = 0;
  bool saveOk = true;
  bool hasExtTextInput = true;

  /// Called when a UNO command is posted; completes when it "returns".
  Future<void> Function(String command, String args)? onUno;

  @override
  int documentType = 1;

  @override
  int get parts => 2;

  @override
  int get part => _part;

  @override
  set part(int value) {
    calls.add('setPart $value');
    _part = value;
  }

  @override
  String partName(int part) => ['Sheet1', 'Daten'][part];

  @override
  int get tileMode => 1;

  @override
  (int, int) get size => (12000, 30000);

  @override
  void initializeForRendering(String argumentsJson) {
    calls.add('initializeForRendering');
    if (readOnly) {
      runtime.emit(LokCallbackType.stateChanged, '.uno:EditDoc=false');
    }
  }

  @override
  void setClientZoom(int a, int b, int c, int d) =>
      calls.add('setClientZoom $a $b $c $d');

  @override
  void setClientVisibleArea(int x, int y, int w, int h) =>
      calls.add('setClientVisibleArea $x $y $w $h');

  @override
  Uint8List paintTile(int part, int pxW, int pxH, int x, int y, int w, int h) {
    calls.add('paintTile $part $pxW $pxH $x $y $w $h');
    return Uint8List(pxW * pxH * 4)..fillRange(0, 4, 255);
  }

  @override
  void postKeyEvent(int type, int charCode, int keyCode) =>
      calls.add('key $type $charCode $keyCode');

  @override
  bool postExtTextInput(int type, String text) {
    if (!hasExtTextInput) return false;
    calls.add('extText $type $text');
    return true;
  }

  @override
  void postMouseEvent(
    int type,
    int x,
    int y,
    int count,
    int buttons,
    int mods,
  ) => calls.add('mouse $type $x $y $count $buttons $mods');

  @override
  void setTextSelection(int type, int x, int y) =>
      calls.add('textSelection $type $x $y');

  @override
  void setGraphicSelection(int type, int x, int y) =>
      calls.add('graphicSelection $type $x $y');

  @override
  void resetSelection() => calls.add('resetSelection');

  @override
  String? textSelection(String mimeType) =>
      mimeType == 'text/html' ? null : 'selected';

  @override
  bool paste(String mimeType, String data) {
    calls.add('paste $mimeType $data');
    return mimeType != 'image/png';
  }

  @override
  Future<void> postUnoCommand(String command, String argumentsJson) async {
    calls.add('uno $command $argumentsJson');
    await onUno?.call(command, argumentsJson);
  }

  @override
  String? commandValues(String command) => '{"commandName":"$command"}';

  @override
  bool saveAs(String path, String format, String filterOptions) {
    calls.add('saveAs $path $format $filterOptions');
    return saveOk;
  }

  @override
  Uint8List paintWindow(int windowId, int x, int y, int w, int h, double dpi) {
    calls.add('paintWindow $windowId $x $y $w $h $dpi');
    return Uint8List(w * h * 4);
  }

  @override
  void postWindow(int windowId, int action) =>
      calls.add('postWindow $windowId $action');

  @override
  void postWindowKeyEvent(int windowId, int type, int charCode, int keyCode) =>
      calls.add('windowKey $windowId $type $charCode $keyCode');

  @override
  void postWindowMouseEvent(
    int windowId,
    int type,
    int x,
    int y,
    int count,
    int buttons,
    int mods,
  ) => calls.add('windowMouse $windowId $type $x $y $count $buttons $mods');

  @override
  void postWindowExtTextInput(int windowId, int type, String text) =>
      calls.add('windowText $windowId $type $text');

  @override
  void destroy() => destroyed = true;
}

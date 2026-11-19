// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// VCL's key codes (`vcl/keycodes.hxx`, `com.sun.star.awt.Key`), which
/// `postKeyEvent` takes; the LibreOfficeKit headers do not carry them.
library;

import 'package:flutter/services.dart';

/// The VCL key codes and modifier bits the editor sends.
abstract final class VclKey {
  static const num0 = 256;
  static const a = 512;
  static const f1 = 768;
  static const down = 1024;
  static const up = 1025;
  static const left = 1026;
  static const right = 1027;
  static const home = 1028;
  static const end = 1029;
  static const pageUp = 1030;
  static const pageDown = 1031;
  static const enter = 1280;
  static const escape = 1281;
  static const tab = 1282;
  static const backspace = 1283;
  static const space = 1284;
  static const insert = 1285;
  static const delete = 1286;

  /// Shift.
  static const shift = 0x1000;

  /// Cmd on macOS (Ctrl elsewhere): how LibreOffice reads the command key.
  static const mod1 = 0x2000;

  /// Option (Alt).
  static const mod2 = 0x4000;

  /// Ctrl on macOS.
  static const mod3 = 0x8000;
}

final _keys = <LogicalKeyboardKey, int>{
  LogicalKeyboardKey.arrowDown: VclKey.down,
  LogicalKeyboardKey.arrowUp: VclKey.up,
  LogicalKeyboardKey.arrowLeft: VclKey.left,
  LogicalKeyboardKey.arrowRight: VclKey.right,
  LogicalKeyboardKey.home: VclKey.home,
  LogicalKeyboardKey.end: VclKey.end,
  LogicalKeyboardKey.pageUp: VclKey.pageUp,
  LogicalKeyboardKey.pageDown: VclKey.pageDown,
  LogicalKeyboardKey.enter: VclKey.enter,
  LogicalKeyboardKey.numpadEnter: VclKey.enter,
  LogicalKeyboardKey.escape: VclKey.escape,
  LogicalKeyboardKey.tab: VclKey.tab,
  LogicalKeyboardKey.backspace: VclKey.backspace,
  LogicalKeyboardKey.delete: VclKey.delete,
  LogicalKeyboardKey.insert: VclKey.insert,
  LogicalKeyboardKey.f2: VclKey.f1 + 1,
};

/// The keys the shell owns: never forwarded (Cmd+S, Cmd+Z, Shift+Cmd+Z,
/// Cmd+W, Cmd+F reach the host through its shortcuts).
final _shellKeys = <LogicalKeyboardKey>{
  LogicalKeyboardKey.keyS,
  LogicalKeyboardKey.keyZ,
  LogicalKeyboardKey.keyW,
  LogicalKeyboardKey.keyF,
};

/// Clipboard keys the editor handles itself (copy, cut, paste).
enum OfficeClipboardKey { copy, cut, paste }

/// What a key event means to the editor.
sealed class OfficeKeyMeaning {
  const OfficeKeyMeaning();
}

/// A VCL key to send (down and up), the modifiers added.
final class OfficeVclKey extends OfficeKeyMeaning {
  const OfficeVclKey(this.keyCode);

  /// The key code with its modifier bits.
  final int keyCode;
}

/// A clipboard command.
final class OfficeClipboardCommand extends OfficeKeyMeaning {
  const OfficeClipboardCommand(this.key);

  /// Which.
  final OfficeClipboardKey key;
}

/// Not the editor's: the shell's shortcut, or text the input method types.
final class OfficeKeyIgnored extends OfficeKeyMeaning {
  const OfficeKeyIgnored();
}

/// What [key] with the modifiers held means to the editor.
OfficeKeyMeaning officeKeyMeaning(
  LogicalKeyboardKey key, {
  required bool shift,
  required bool meta,
  required bool alt,
  required bool control,
}) {
  var mods = 0;
  if (shift) mods |= VclKey.shift;
  if (meta) mods |= VclKey.mod1;
  if (alt) mods |= VclKey.mod2;
  if (control) mods |= VclKey.mod3;
  final special = _keys[key];
  if (special != null) return OfficeVclKey(special | mods);
  if (!meta) return const OfficeKeyIgnored(); // text: the input method's
  if (_shellKeys.contains(key)) return const OfficeKeyIgnored();
  if (!shift && !alt) {
    if (key == LogicalKeyboardKey.keyC) {
      return const OfficeClipboardCommand(OfficeClipboardKey.copy);
    }
    if (key == LogicalKeyboardKey.keyX) {
      return const OfficeClipboardCommand(OfficeClipboardKey.cut);
    }
    if (key == LogicalKeyboardKey.keyV) {
      return const OfficeClipboardCommand(OfficeClipboardKey.paste);
    }
  }
  // Cmd+B / I / U and the other LibreOffice shortcuts.
  final letter = key.keyId - LogicalKeyboardKey.keyA.keyId;
  if (letter >= 0 && letter < 26) {
    return OfficeVclKey((VclKey.a + letter) | mods);
  }
  final digit = key.keyId - LogicalKeyboardKey.digit0.keyId;
  if (digit >= 0 && digit < 10) {
    return OfficeVclKey((VclKey.num0 + digit) | mods);
  }
  return const OfficeKeyIgnored();
}

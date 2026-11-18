// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The exports of the helper's C part (`src/lok_trampoline.c`), built by the
/// package's build hook.
///
/// Where the dylib is found:
///
/// 1. **Beside the executable** (`libtom_office_host_lok.dylib`): the helper
///    as it lies in the binaries layer, where the `dart build cli` bundle is
///    flattened into one folder (DPPK-2).
/// 2. **Otherwise through Dart's code-asset mapping** (`@Native`): under
///    `dart run` and `dart test` (the hook's output), and in the unflattened
///    bundle, whose snapshot names the dylib as `../lib/<name>` relative to
///    the executable.
///
/// The mapping is a path in the snapshot, not a Mach-O load command, so
/// `install_name_tool` cannot redirect it; hence the first step.
@DefaultAsset('package:tom_office_host/lok_trampoline.dart')
library;

import 'dart:ffi';
import 'dart:io';

import 'lok_bindings.g.dart';

/// The trampoline's file name.
const kTrampolineFileName = 'libtom_office_host_lok.dylib';

/// The Dart listener's native signature: type, the payload copy (freed by
/// Dart with [tomLokFree]), its length, and the tag given to
/// `registerCallback`.
typedef TomLokListenerNative =
    Void Function(Int32, Pointer<Char>, Int64, IntPtr);

typedef _InitN = Pointer<LibreOfficeKit> Function(Pointer<Char>, Pointer<Char>);
typedef _SetListenerN =
    Void Function(Pointer<NativeFunction<TomLokListenerNative>>);
typedef _CallbackPointerN = LibreOfficeKitCallback Function();
typedef _FreeN = Void Function(Pointer<Void>);
typedef _SetPasswordN = Void Function(Pointer<LibreOfficeKit>, Pointer<Char>);
typedef _AskedN = Int Function();

@Native<_InitN>(symbol: 'tom_lok_init_2')
external Pointer<LibreOfficeKit> _init2(Pointer<Char> a, Pointer<Char> b);

@Native<_SetListenerN>(symbol: 'tom_lok_set_listener')
external void _setListener(
  Pointer<NativeFunction<TomLokListenerNative>> listener,
);

@Native<_CallbackPointerN>(symbol: 'tom_lok_callback_pointer')
external LibreOfficeKitCallback _callbackPointer();

@Native<_FreeN>(symbol: 'tom_lok_free')
external void _free(Pointer<Void> pointer);

@Native<_SetPasswordN>(symbol: 'tom_lok_set_password_answer')
external void _setPassword(Pointer<LibreOfficeKit> kit, Pointer<Char> pw);

@Native<_AskedN>(symbol: 'tom_lok_password_asked')
external int _asked();

/// Where the trampoline was loaded from: the path beside the executable, or
/// `null` for Dart's code-asset mapping.
String? get trampolineSource => _Trampoline.instance.source;

/// The trampoline's exports, resolved once.
final class _Trampoline {
  _Trampoline._(this.source, DynamicLibrary? lib)
    : init2 = lib == null
          ? _init2
          : lib.lookupFunction<
              _InitN,
              Pointer<LibreOfficeKit> Function(Pointer<Char>, Pointer<Char>)
            >('tom_lok_init_2'),
      setListener = lib == null
          ? _setListener
          : lib.lookupFunction<
              _SetListenerN,
              void Function(Pointer<NativeFunction<TomLokListenerNative>>)
            >('tom_lok_set_listener'),
      callbackPointer = lib == null
          ? _callbackPointer
          : lib.lookupFunction<
              _CallbackPointerN,
              LibreOfficeKitCallback Function()
            >('tom_lok_callback_pointer'),
      free = lib == null
          ? _free
          : lib.lookupFunction<_FreeN, void Function(Pointer<Void>)>(
              'tom_lok_free',
            ),
      setPassword = lib == null
          ? _setPassword
          : lib.lookupFunction<
              _SetPasswordN,
              void Function(Pointer<LibreOfficeKit>, Pointer<Char>)
            >('tom_lok_set_password_answer'),
      asked = lib == null
          ? _asked
          : lib.lookupFunction<_AskedN, int Function()>(
              'tom_lok_password_asked',
            );

  static final instance = _load();

  static _Trampoline _load() {
    final beside =
        '${File(Platform.resolvedExecutable).parent.path}'
        '${Platform.pathSeparator}$kTrampolineFileName';
    if (File(beside).existsSync()) {
      return _Trampoline._(beside, DynamicLibrary.open(beside));
    }
    return _Trampoline._(null, null);
  }

  final String? source;
  final Pointer<LibreOfficeKit> Function(Pointer<Char>, Pointer<Char>) init2;
  final void Function(Pointer<NativeFunction<TomLokListenerNative>>)
  setListener;
  final LibreOfficeKitCallback Function() callbackPointer;
  final void Function(Pointer<Void>) free;
  final void Function(Pointer<LibreOfficeKit>, Pointer<Char>) setPassword;
  final int Function() asked;
}

/// `lok_init_2`, which the header defines static inline.
Pointer<LibreOfficeKit> tomLokInit2(
  Pointer<Char> installPath,
  Pointer<Char> userProfileUrl,
) => _Trampoline.instance.init2(installPath, userProfileUrl);

/// Sets the Dart listener every callback is handed to.
void tomLokSetListener(
  Pointer<NativeFunction<TomLokListenerNative>> listener,
) => _Trampoline.instance.setListener(listener);

/// The callback to register with LibreOfficeKit.
LibreOfficeKitCallback tomLokCallbackPointer() =>
    _Trampoline.instance.callbackPointer();

/// Frees a payload copy.
void tomLokFree(Pointer<Void> pointer) => _Trampoline.instance.free(pointer);

/// Arms the answer to the next password request (`nullptr`: cancel).
void tomLokSetPasswordAnswer(
  Pointer<LibreOfficeKit> kit,
  Pointer<Char> password,
) => _Trampoline.instance.setPassword(kit, password);

/// The password kinds asked for since the last arming (see the C source).
int tomLokPasswordAsked() => _Trampoline.instance.asked();

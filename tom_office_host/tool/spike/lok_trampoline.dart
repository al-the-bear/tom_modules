// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The C trampoline's exports (native/lok_trampoline.c), built by the
/// package's build hook. Spike code.
@DefaultAsset('package:tom_office_host/spike/lok_trampoline.dart')
library;

import 'dart:ffi';

import 'lok_bindings.g.dart';

/// The Dart listener's native signature: type, the payload copy (freed by
/// Dart), the payload's length and FNV-1a hash as LibreOffice passed it,
/// and the tag given to `registerCallback`.
typedef TomLokListenerNative =
    Void Function(Int32, Pointer<Char>, Int64, Uint64, IntPtr);

@Native<Pointer<LibreOfficeKit> Function(Pointer<Char>, Pointer<Char>)>(
  symbol: 'tom_lok_init_2',
)
external Pointer<LibreOfficeKit> tomLokInit2(
  Pointer<Char> installPath,
  Pointer<Char> userProfileUrl,
);

@Native<Void Function(Pointer<NativeFunction<TomLokListenerNative>>)>(
  symbol: 'tom_lok_set_listener',
)
external void tomLokSetListener(
  Pointer<NativeFunction<TomLokListenerNative>> listener,
);

@Native<Long Function()>(symbol: 'tom_lok_callback_count')
external int tomLokCallbackCount();

@Native<LibreOfficeKitCallback Function()>(symbol: 'tom_lok_callback_pointer')
external LibreOfficeKitCallback tomLokCallbackPointer();

@Native<Void Function(Pointer<Void>)>(symbol: 'tom_lok_free')
external void tomLokFree(Pointer<Void> pointer);

@Native<Uint64 Function(Pointer<Char>, Int64)>(symbol: 'tom_lok_fnv1a')
external int tomLokFnv1a(Pointer<Char> text, int length);

@Native<Void Function(Pointer<LibreOfficeKit>, Pointer<Char>)>(
  symbol: 'tom_lok_set_password_answer',
)
external void tomLokSetPasswordAnswer(
  Pointer<LibreOfficeKit> kit,
  Pointer<Char> password,
);

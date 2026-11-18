// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The exports of the helper's C part (`src/lok_trampoline.c`), built by the
/// package's build hook.
@DefaultAsset('package:tom_office_host/lok_trampoline.dart')
library;

import 'dart:ffi';

import 'lok_bindings.g.dart';

/// The Dart listener's native signature: type, the payload copy (freed by
/// Dart with [tomLokFree]), its length, and the tag given to
/// `registerCallback`.
typedef TomLokListenerNative =
    Void Function(Int32, Pointer<Char>, Int64, IntPtr);

/// `lok_init_2`, which the header defines static inline.
@Native<Pointer<LibreOfficeKit> Function(Pointer<Char>, Pointer<Char>)>(
  symbol: 'tom_lok_init_2',
)
external Pointer<LibreOfficeKit> tomLokInit2(
  Pointer<Char> installPath,
  Pointer<Char> userProfileUrl,
);

/// Sets the Dart listener every callback is handed to.
@Native<Void Function(Pointer<NativeFunction<TomLokListenerNative>>)>(
  symbol: 'tom_lok_set_listener',
)
external void tomLokSetListener(
  Pointer<NativeFunction<TomLokListenerNative>> listener,
);

/// The callback to register with LibreOfficeKit.
@Native<LibreOfficeKitCallback Function()>(symbol: 'tom_lok_callback_pointer')
external LibreOfficeKitCallback tomLokCallbackPointer();

/// Frees a payload copy.
@Native<Void Function(Pointer<Void>)>(symbol: 'tom_lok_free')
external void tomLokFree(Pointer<Void> pointer);

/// Arms the answer to the next password request (`nullptr`: cancel).
@Native<Void Function(Pointer<LibreOfficeKit>, Pointer<Char>)>(
  symbol: 'tom_lok_set_password_answer',
)
external void tomLokSetPasswordAnswer(
  Pointer<LibreOfficeKit> kit,
  Pointer<Char> password,
);

/// The password kinds asked for since the last arming (see the C source).
@Native<Int Function()>(symbol: 'tom_lok_password_asked')
external int tomLokPasswordAsked();

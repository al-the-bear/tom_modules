/// Installing page script for the browser tests, so that a recorder replacing
/// a browser API runs as the page's own JavaScript and receives `this` and the
/// arguments the code under test passes.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Runs [source] as a script of the page.
void runPageScript(String source) {
  final script = web.document.createElement('script') as web.HTMLScriptElement
    ..text = source;
  web.document.head!.appendChild(script);
  script.remove();
}

/// The page's global object.
JSObject get pageWindow => globalContext;

/// The string [name] of [of], or null.
String? stringOf(JSObject of, String name) => (of[name] as JSString?)?.toDart;

/// The number [name] of [of].
int intOf(JSObject of, String name) => (of[name] as JSNumber).toDartInt;

/// The boolean [name] of [of].
bool boolOf(JSObject of, String name) => (of[name] as JSBoolean).toDart;

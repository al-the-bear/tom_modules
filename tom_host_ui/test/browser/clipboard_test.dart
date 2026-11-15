/// `tomPlaceOnBrowserClipboard` — both flavours in one `ClipboardItem`.
///
/// On the VM the conditional import selects the stub, which answers `failed`.
/// These tests run the browser half on Chrome.
///
/// **What is observed.** `navigator.clipboard.write` is replaced, for the
/// duration of a test, by a recorder that reads back every flavour of every
/// item it is handed. No permission prompt opens and the clipboard of whoever
/// runs the suite is left alone.
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:tom_host_ui/web.dart';

import 'page_script.dart';

const _recorder = '''
(function () {
  var rec = window.__tomClip = { calls: [], reject: false };
  navigator.clipboard.write = function (items) {
    var call = { count: items.length, types: [], texts: {} };
    rec.calls.push(call);
    var item = items[0];
    call.types = Array.from(item.types);
    call.done = Promise.all(call.types.map(function (type) {
      return item.getType(type)
        .then(function (blob) { return blob.text(); })
        .then(function (text) { call.texts[type] = text; });
    }));
    return rec.reject
      ? Promise.reject(new DOMException('denied', 'NotAllowedError'))
      : Promise.resolve();
  };
})();
''';

const _restore = 'delete navigator.clipboard.write;';

JSObject get _record => pageWindow['__tomClip'] as JSObject;

List<JSObject> get _calls => (_record['calls'] as JSArray<JSObject>).toDart;

const _html = '<p><b>Plan</b> — <i>draft</i></p>';
const _text = 'Plan — draft';

void main() {
  setUp(() => runPageScript(_recorder));
  tearDown(() => runPageScript(_restore));

  test('RUI-B3: one write carrying one item with exactly text/html and '
      'text/plain, holding the given contents', () async {
    final placement = await tomPlaceOnBrowserClipboard(
      html: _html,
      text: _text,
    );

    expect(placement, TomClipboardPlacement.both);
    expect(
      _calls,
      hasLength(1),
      reason: 'one placement, so the two flavours cannot race',
    );
    final call = _calls.single;
    expect(intOf(call, 'count'), 1, reason: 'one ClipboardItem');
    final types = [
      for (final t in (call['types'] as JSArray<JSString>).toDart) t.toDart,
    ];
    expect(types, unorderedEquals(['text/html', 'text/plain']));

    await (call['done'] as JSPromise<JSAny?>).toDart;
    final texts = call['texts'] as JSObject;
    expect(stringOf(texts, 'text/html'), _html);
    expect(stringOf(texts, 'text/plain'), _text);
  });

  test('RUI-B4: a write the browser rejects answers failed', () async {
    _record['reject'] = true.toJS;

    final placement = await tomPlaceOnBrowserClipboard(
      html: _html,
      text: _text,
    );

    expect(placement, TomClipboardPlacement.failed);
    expect(_calls, hasLength(1), reason: 'the write was attempted');
  });
}

/// `tomPrintHtmlInBrowser` — the hidden iframe the browser's print dialog
/// renders the document in.
///
/// On the VM the conditional import selects the stub, so the suite there
/// exercises only "this process cannot print". These tests run the browser
/// half on Chrome.
///
/// **What is observed.** A capture-phase `load` listener on the document runs
/// before the frame's own `onload`, after the `srcdoc` document has loaded, so
/// it can replace that document's window's `print()` with a recorder: the
/// recorder notes what the frame held when it was asked to print, and no print
/// dialog opens. A mutation observer counts the frames appended to the body.
/// Replacing `print()` any earlier would not survive: the `srcdoc` navigation
/// gives the frame a new window.
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:tom_host_ui/web.dart';

import 'page_script.dart';

const _recorder = '''
(function () {
  var rec = window.__tomPrint = { appended: [], printed: 0, atPrint: null };
  window.__tomPrintObserver = new MutationObserver(function (mutations) {
    mutations.forEach(function (m) {
      m.addedNodes.forEach(function (n) {
        if (n.tagName === 'IFRAME') rec.appended.push(n);
      });
    });
  });
  window.__tomPrintObserver.observe(document.body, { childList: true });
  window.__tomPrintLoad = function (event) {
    var frame = event.target;
    if (!frame || frame.tagName !== 'IFRAME') return;
    frame.contentWindow.print = function () {
      rec.printed++;
      rec.atPrint = {
        connected: frame.isConnected,
        srcdoc: frame.srcdoc,
        width: frame.style.width,
        height: frame.style.height,
        position: frame.style.position,
        text: frame.contentDocument.body.textContent
      };
    };
  };
  document.addEventListener('load', window.__tomPrintLoad, true);
})();
''';

const _restore = '''
window.__tomPrintObserver.disconnect();
document.removeEventListener('load', window.__tomPrintLoad, true);
''';

JSObject get _record => pageWindow['__tomPrint'] as JSObject;

List<JSObject> get _appended =>
    (_record['appended'] as JSArray<JSObject>).toDart;

const _html =
    '<!DOCTYPE html><html><head><title>Plan</title></head>'
    '<body><h1>Quarterly plan</h1><p>Ünïcode — kept.</p></body></html>';

void main() {
  setUp(() => runPageScript(_recorder));
  tearDown(() => runPageScript(_restore));

  test('RUI-B1: one hidden frame holding the document is asked to print '
      'once, then removed', () async {
    final label = await tomPrintHtmlInBrowser('Plan', _html);

    expect(
      label,
      isNotNull,
      reason: 'the stub answers null; this run must be the browser half',
    );
    expect(_appended, hasLength(1), reason: 'exactly one frame was appended');
    expect(intOf(_record, 'printed'), 1);

    final atPrint = _record['atPrint'] as JSObject;
    expect(
      boolOf(atPrint, 'connected'),
      isTrue,
      reason: 'the frame was in the document while it printed',
    );
    expect(stringOf(atPrint, 'srcdoc'), _html);
    expect(
      stringOf(atPrint, 'text'),
      contains('Ünïcode — kept.'),
      reason: 'the frame rendered the given HTML, not an empty document',
    );
    expect(stringOf(atPrint, 'position'), 'fixed');
    expect(stringOf(atPrint, 'width'), '0px');
    expect(stringOf(atPrint, 'height'), '0px');

    expect(
      boolOf(_appended.single, 'isConnected'),
      isFalse,
      reason: 'the frame is removed once printing is over',
    );
  });

  test('RUI-B2: two jobs leave no frame behind', () async {
    await tomPrintHtmlInBrowser('One', _html);
    await tomPrintHtmlInBrowser('Two', _html);

    expect(_appended, hasLength(2));
    expect(intOf(_record, 'printed'), 2);
    for (final frame in _appended) {
      expect(boolOf(frame, 'isConnected'), isFalse);
    }
  });
}

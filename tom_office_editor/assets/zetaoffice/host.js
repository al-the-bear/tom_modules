// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause
//
// The main thread of TomZetaOfficeView's page. The query names the cached
// ZetaOffice files (`zeta`), the document (`doc`, `name`) and where the saved
// bytes go (`save`, `copy`). Everything the page says goes to Dart through the
// `forge` JavaScript handler; Dart calls `window.forgeBridge`.
'use strict';
(function () {
  const params = new URLSearchParams(location.search);
  const abs = (p) => new URL(p, location.href).href;
  const zetaBase = abs(params.get('zeta') || '../zeta/');
  const docUrl = params.get('doc');
  const name = params.get('name') || 'document';
  const saveUrl = params.get('save');
  const copyUrl = params.get('copy');
  const dir = '/tmp/office';
  const docPath = dir + '/' + name;

  function post(message) {
    try {
      window.flutter_inappwebview.callHandler('forge', message);
    } catch (e) {
      console.log('forge ' + JSON.stringify(message));
    }
  }
  function trail(text) { post({ type: 'trail', text: String(text) }); }

  // ZetaOffice runs threads on SharedArrayBuffer: only a cross-origin
  // isolated page has it.
  if (!window.crossOriginIsolated) {
    post({
      type: 'error', code: 'notIsolated',
      message: 'The page is not cross-origin isolated (crossOriginIsolated is false).',
    });
    return;
  }

  let port = null;
  const fs = () => window.FS || window.Module.FS;

  window.Module = {
    canvas: document.getElementById('qtcanvas'),
    // Absolute: they are loaded by a worker whose script is a blob.
    uno_scripts: [abs('zeta.js'), abs('office_thread.js')],
    locateFile: (path, prefix) => (prefix || zetaBase) + path,
    // soffice.js is not beside this page: its worker loads it from the cache.
    mainScriptUrlOrBlob: new Blob(
      ["importScripts('" + zetaBase + "soffice.js');"], { type: 'text/javascript' }),
    setStatus: (text) => { if (text) post({ type: 'status', text: String(text) }); },
    printErr: (text) => { if (/error|exception/i.test(text)) trail('stderr: ' + text); },
  };
  // Qt follows the canvas's size on resize events.
  setInterval(() => window.dispatchEvent(new Event('resize')), 1000);

  function send(message) {
    if (port) {
      port.postMessage(message);
    } else {
      post({ type: 'error', code: 'notReady', message: 'ZetaOffice is not ready' });
    }
  }

  const filters = {
    docx: 'MS Word 2007 XML', xlsx: 'Calc MS Excel 2007 XML',
    pptx: 'Impress MS PowerPoint 2007 XML', odt: 'writer8', ods: 'calc8',
    odp: 'impress8', doc: 'MS Word 97', xls: 'MS Excel 97',
    ppt: 'MS PowerPoint 97', rtf: 'Rich Text Format', csv: 'Text - txt - csv (StarCalc)',
  };
  const ext = name.includes('.') ? name.split('.').pop().toLowerCase() : '';

  window.forgeBridge = {
    save() { send({ cmd: 'save' }); },
    saveCopy() {
      send({ cmd: 'saveCopy', url: 'file://' + dir + '/copy/' + name, filter: filters[ext] || '' });
    },
    undo() { send({ cmd: 'undo' }); },
    redo() { send({ cmd: 'redo' }); },
    // Test hooks: an edit through UNO, and the text read back.
    edit(text) { send({ cmd: 'edit', text: String(text) }); },
    read() { send({ cmd: 'read' }); },
  };

  async function postBytes(url, path) {
    const bytes = fs().readFile(path);
    const response = await fetch(url, { method: 'POST', body: bytes });
    if (!response.ok) throw new Error('POST answered ' + response.status);
    return bytes.length;
  }

  const script = document.createElement('script');
  script.src = zetaBase + 'soffice.js';
  // Module.uno_main exists only once soffice.js has loaded.
  script.addEventListener('load', () => {
    post({ type: 'status', text: 'soffice.js loaded' });
    window.Module.uno_main.then(async (p) => {
      port = p;
      port.onmessage = async (event) => {
        const m = event.data;
        if (m.type === 'stored') {
          if (!m.ok) {
            post({ type: 'saved', ok: false, copy: !!m.copy, error: m.error });
            return;
          }
          try {
            const n = await postBytes(m.copy ? copyUrl : saveUrl, m.path);
            post({ type: 'saved', ok: true, copy: !!m.copy, bytes: n });
          } catch (e) {
            post({ type: 'saved', ok: false, copy: !!m.copy, error: String(e) });
          }
          return;
        }
        post(m);
      };
      try {
        const response = await fetch(docUrl);
        if (!response.ok) throw new Error('the document answered ' + response.status);
        const bytes = new Uint8Array(await response.arrayBuffer());
        try { fs().mkdirTree(dir + '/copy'); } catch (e) { /* there already */ }
        fs().writeFile(docPath, bytes);
        port.postMessage({ cmd: 'load', url: 'file://' + docPath, name });
      } catch (e) {
        post({ type: 'error', code: 'loadFailed', message: String(e) });
      }
    });
  });
  script.addEventListener('error', () => post({
    type: 'error', code: 'scriptFailed', message: 'soffice.js did not load',
  }));
  document.body.appendChild(script);
  post({ type: 'status', text: 'starting ZetaOffice' });
})();

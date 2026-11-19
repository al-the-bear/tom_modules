// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause
//
// ZetaOffice's office thread (Module.uno_scripts, after zeta.js): loads the
// document, reports its modified state and history, stores it, runs undo and
// redo. Messages to and from the page go through zetajs.mainPort.
'use strict';

let zetajs, css, context, desktop, toolkit, dispatcher;
let xModel = null;

function post(message) { zetajs.mainPort.postMessage(message); }

function kindOf(model) {
  if (model.queryInterface(zetajs.type.interface(css.text.XTextDocument))) return 'text';
  if (model.queryInterface(zetajs.type.interface(css.sheet.XSpreadsheetDocument))) return 'spreadsheet';
  if (model.queryInterface(zetajs.type.interface(css.drawing.XDrawPagesSupplier))) return 'presentation';
  return 'other';
}

function product() {
  try {
    const provider = css.configuration.theDefaultProvider(context);
    const access = provider.createInstanceWithArguments(
      'com.sun.star.configuration.ConfigurationAccess',
      [new css.beans.PropertyValue({ Name: 'nodepath', Value: '/org.openoffice.Setup/Product' })]);
    return zetajs.fromAny(access.getByName('ooName')) + ' ' +
      zetajs.fromAny(access.getByName('ooSetupVersionAboutBox'));
  } catch (e) {
    return '';
  }
}

function history() {
  try {
    const undo = xModel.getUndoManager();
    post({ type: 'history', canUndo: undo.isUndoPossible(), canRedo: undo.isRedoPossible() });
  } catch (e) { /* no undo manager */ }
}

function modified() {
  try { post({ type: 'modified', value: xModel.isModified() }); } catch (e) { /* gone */ }
  history();
}

function frame() { return xModel.getCurrentController().getFrame(); }

function load(url) {
  xModel = desktop.loadComponentFromURL(url, '_default', 0, []);
  xModel.addModifyListener(zetajs.unoObject([css.util.XModifyListener], {
    modified() { modified(); },
    disposing() {},
  }));
  // The document's window fills the canvas.
  setInterval(() => { try { toolkit.getActiveTopWindow().FullScreen = true; } catch (e) { /* none */ } }, 1000);
  post({ type: 'loaded', kind: kindOf(xModel), product: product() });
  modified();
}

function store(copy, url, filter) {
  try {
    if (copy) {
      // A copy: the flag stays set, as UNO defines storeToURL.
      xModel.storeToURL(url, [new css.beans.PropertyValue({ Name: 'FilterName', Value: filter })]);
      post({ type: 'stored', ok: true, copy: true, path: url.replace('file://', '') });
    } else {
      // In place, in its own format: clears the modified flag.
      xModel.store();
      post({ type: 'stored', ok: true, copy: false, path: zetajs.fromAny(xModel.getURL()).replace('file://', '') });
      modified();
    }
  } catch (e) {
    let message = String(e);
    try { message = String(zetajs.getAnyType(zetajs.catchUnoException(e))); } catch (x) { /* plain JS error */ }
    post({ type: 'stored', ok: false, copy, error: message });
  }
}

function dispatch(command) {
  dispatcher.executeDispatch(frame(), command, '', 0, []);
  modified();
}

// Test hooks: an edit through UNO at the start of the document, and its text.
function target(kind) {
  if (kind === 'text') return xModel.getText();
  if (kind === 'spreadsheet') return xModel.getSheets().getByIndex(0).getCellByPosition(0, 0);
  if (kind === 'presentation') return xModel.getDrawPages().getByIndex(0).getByIndex(0);
  return null;
}

function edit(text) {
  const kind = kindOf(xModel);
  const t = target(kind);
  if (kind === 'text') {
    t.insertString(t.getStart(), text, false);
  } else {
    t.setString(text + t.getString());
  }
  // Impress raises no modify event for a shape's text set through UNO
  // (Writer and Calc do): the change is real, so the flag is set here.
  if (!xModel.isModified()) xModel.setModified(true);
  modified();
}

function read() {
  const t = target(kindOf(xModel));
  post({ type: 'text', text: t ? t.getString() : '' });
}

Module.zetajs.then(function (pZetajs) {
  zetajs = pZetajs;
  css = zetajs.uno.com.sun.star;
  context = zetajs.getUnoComponentContext();
  desktop = css.frame.Desktop.create(context);
  toolkit = css.awt.Toolkit.create(context);
  dispatcher = css.frame.DispatchHelper.create(context);
  zetajs.mainPort.onmessage = function (event) {
    const m = event.data;
    try {
      switch (m.cmd) {
        case 'load': load(m.url); break;
        case 'save': store(false); break;
        case 'saveCopy': store(true, m.url, m.filter); break;
        case 'undo': dispatch('.uno:Undo'); break;
        case 'redo': dispatch('.uno:Redo'); break;
        case 'edit': edit(m.text); break;
        case 'read': read(); break;
      }
    } catch (e) {
      post({ type: 'error', code: m.cmd + 'Failed', message: String(e) });
    }
  };
  post({ type: 'ready' });
});

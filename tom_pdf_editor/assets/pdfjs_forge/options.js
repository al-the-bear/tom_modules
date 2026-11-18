// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

// Forge's options for pdf.js's generic viewer, set when it announces itself
// (`webviewerloaded`) and before it starts: nothing loads before Dart asks,
// nothing is stored in the webview, no JavaScript inside a PDF runs.
// A classic script, so it is listening before viewer.mjs runs.
"use strict";
document.addEventListener("webviewerloaded", () => {
  const readOnly = new URLSearchParams(location.search).get("readonly") === "1";
  window.PDFViewerApplicationOptions.setAll({
    defaultUrl: "",
    disablePreferences: true,
    disableHistory: true,
    enableScripting: false,
    // Gone from pdf.js 6.5 (it no longer uses eval); kept so an older
    // release would get it too. Unknown options are ignored.
    isEvalSupported: false,
    enableXfa: false,
    // The editor available, no tool chosen; -1 hides the tools.
    annotationEditorMode: readOnly ? -1 : 0,
    // Links are caught by the bridge and go to Dart.
    externalLinkTarget: 0,
    // Signatures are stored in the webview: off.
    enableSignatureEditor: false,
  });
});

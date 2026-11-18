// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

// The bridge on pdf.js's generic viewer (`integrated` and `full` modes).
import { installBridge, trail } from "./bridge.mjs";

const app = window.PDFViewerApplication;
await app.initializedPromise;
trail("generic viewer initialised");

installBridge({
  mode: "generic",
  eventBus: app.eventBus,
  async open(url, onPassword) {
    const opening = app.open({ url });
    const task = app.pdfLoadingTask;
    let failure = null;
    task?.promise.catch((e) => (failure = e));
    if (task) {
      const ask = task.onPassword;
      task.onPassword = (update, reason) => {
        onPassword();
        return ask?.(update, reason);
      };
    }
    await opening;
    if (!app.pdfDocument) {
      throw failure ?? new Error("pdf.js could not open the document");
    }
    return app.pdfDocument;
  },
  async close() {
    await app.close();
  },
  setTool(mode) {
    app.eventBus.dispatch("switchannotationeditormode", {
      source: window,
      mode,
    });
  },
  view() {
    return { page: app.page, scale: app.pdfViewer.currentScaleValue };
  },
  scrollTo(page) {
    app.page = page;
  },
  zoom(how) {
    if (how === "in") app.zoomIn();
    else if (how === "out") app.zoomOut();
    else app.pdfViewer.currentScaleValue = how;
  },
});

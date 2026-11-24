// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

// The bridge between a pdf.js page and Dart (TomPdfJsController), shared by
// the three modes. Dart calls `window.forgeBridge.<function>(...)` through
// evaluateJavascript and never waits on the page: every function returns at
// once, and everything the page has to say goes back through the
// `forge` JavaScript handler as `{type, ...}` messages.
//
// An adapter connects it to one kind of page: the generic viewer
// (generic.mjs) or our components page (components.mjs). It provides
//   open(url, onPassword) → Promise<PDFDocumentProxy>, close(), eventBus,
//   setTool(mode), zoom(how), uiManager (when known).

const queue = [];
let platformReady = false;

/** Sends a message to Dart (queued until the webview's bridge is ready). */
export function send(message) {
  if (platformReady && window.flutter_inappwebview?.callHandler) {
    window.flutter_inappwebview.callHandler("forge", message);
  } else {
    queue.push(message);
  }
}

window.addEventListener("flutterInAppWebViewPlatformReady", () => {
  platformReady = true;
  while (queue.length) {
    window.flutter_inappwebview.callHandler("forge", queue.shift());
  }
});
if (window.flutter_inappwebview?.callHandler) platformReady = true;

/** A short line for Dart's debug trail (never document content). */
export function trail(text) {
  send({ type: "trail", text: String(text).slice(0, 300) });
}

const consoleError = console.error.bind(console);
console.error = (...args) => {
  consoleError(...args);
  send({
    type: "trail",
    text: "console.error: " + args.map(String).join(" ").slice(0, 300),
  });
};
window.addEventListener("unhandledrejection", (e) => {
  send({ type: "trail", text: "unhandled: " + String(e.reason).slice(0, 300) });
});

export function installBridge(adapter) {
  let doc = null;
  let opening = 0;
  const bus = adapter.eventBus;

  // pdf.js 6 names it `editingstateschanged`; older releases
  // `annotationeditorstateschanged`.
  const onStates = ({ details }) => {
    if (
      details &&
      ("hasSomethingToUndo" in details || "hasSomethingToRedo" in details)
    ) {
      send({
        type: "history",
        canUndo: !!details.hasSomethingToUndo,
        canRedo: !!details.hasSomethingToRedo,
      });
    }
  };
  bus.on("editingstateschanged", onStates);
  bus.on("annotationeditorstateschanged", onStates);
  bus.on("updatefindmatchescount", ({ matchesCount }) => {
    send({
      type: "findCount",
      current: matchesCount?.current ?? 0,
      total: matchesCount?.total ?? 0,
    });
  });
  // Where the view stands, for the host to keep and give back.
  let viewTimer = null;
  const sendView = () => {
    clearTimeout(viewTimer);
    viewTimer = setTimeout(() => {
      const view = adapter.view?.();
      if (view) send({ type: "view", page: view.page, scale: String(view.scale) });
    }, 150);
  };
  bus.on("pagechanging", sendView);
  bus.on("scalechanging", sendView);

  bus.on("annotationeditormodechanged", ({ mode }) => {
    send({ type: "tool", mode });
  });
  bus.on("annotationeditoruimanager", ({ uiManager }) => {
    adapter.uiManager = uiManager;
  });

  // Links leave the webview through Dart; the page never navigates away.
  document.addEventListener(
    "click",
    (e) => {
      const a = e.target?.closest?.("a[href]");
      if (!a) return;
      const url = new URL(a.href, location.href);
      if (url.origin === location.origin || url.protocol === "javascript:") {
        return;
      }
      e.preventDefault();
      e.stopPropagation();
      send({ type: "openLink", url: url.href });
    },
    true,
  );

  // Cmd+S and Cmd+F belong to the shell.
  window.addEventListener(
    "keydown",
    (e) => {
      if (!(e.metaKey || e.ctrlKey) || e.altKey) return;
      const key = e.key.toLowerCase();
      if (key !== "s" && key !== "f") return;
      e.preventDefault();
      e.stopImmediatePropagation();
      send({ type: "shortcut", key: key === "s" ? "save" : "find" });
    },
    true,
  );

  async function hasText(pdf) {
    for (let i = 1; i <= Math.min(3, pdf.numPages); i++) {
      const page = await pdf.getPage(i);
      const text = await page.getTextContent();
      if (text.items.some((item) => item.str && item.str.trim())) return true;
    }
    return false;
  }

  // The open document's modified state, as its storage's hooks last
  // reported it: pdf.js keeps the state in a private field (no getter).
  let modified = false;

  // The storage's modified hooks report to Dart. The generic viewer sets
  // its own hooks after the document has opened, so whatever is assigned
  // later is chained, not replaced.
  function chain(storage, name, value) {
    let inner = storage[name];
    Object.defineProperty(storage, name, {
      configurable: true,
      get() {
        return () => {
          inner?.();
          if (storage === doc?.annotationStorage) modified = value;
          send({ type: "modified", value });
        };
      },
      set(f) {
        inner = f;
      },
    });
  }

  function watch(pdf) {
    modified = false;
    chain(pdf.annotationStorage, "onSetModified", true);
    chain(pdf.annotationStorage, "onResetModified", false);
  }

  const bridge = {
    /** Opens [url]; the previous document is closed first. */
    open(url) {
      const ticket = ++opening;
      const started = performance.now();
      (async () => {
        try {
          if (doc) {
            const closing = performance.now();
            doc = null;
            await adapter.close();
            trail(`closed the previous document in ${Math.round(performance.now() - closing)} ms`);
          }
          const pdf = await adapter.open(url, () =>
            send({ type: "passwordRequested" }),
          );
          if (ticket !== opening) return;
          doc = pdf;
          watch(pdf);
          send({
            type: "loaded",
            pageCount: pdf.numPages,
            ms: Math.round(performance.now() - started),
          });
          send({ type: "textLayer", value: await hasText(pdf) });
        } catch (e) {
          if (ticket !== opening) return;
          send({
            type: "error",
            kind: e?.name === "PasswordException" ? "password" : "open",
            message: String(e?.message ?? e),
          });
        }
      })();
    },

    /** Closes the document. */
    close() {
      opening++;
      doc = null;
      adapter.close().catch((e) => trail("close: " + e));
    },

    /** saveDocument(), the bytes POSTed to [saveUrl]; then `saved`. */
    save(saveUrl) {
      (async () => {
        try {
          if (!doc) throw new Error("no document");
          const started = performance.now();
          const data = await doc.saveDocument();
          const response = await fetch(saveUrl, {
            method: "POST",
            headers: { "Content-Type": "application/pdf" },
            body: data,
          });
          send({
            type: "saved",
            ok: response.ok,
            status: response.status,
            size: data.length,
            ms: Math.round(performance.now() - started),
          });
        } catch (e) {
          send({ type: "error", kind: "save", message: String(e?.message ?? e) });
        }
      })();
    },

    /** The document is clean (after Dart wrote the saved bytes). */
    resetModified() {
      doc?.annotationStorage.resetModified();
    },

    /** Reports `modified` as it is now. */
    checkModified() {
      send({ type: "modified", value: !!doc && modified });
    },

    undo() {
      bus.dispatch("editingaction", { source: window, name: "undo" });
    },

    redo() {
      bus.dispatch("editingaction", { source: window, name: "redo" });
    },

    /** Searches; [options]: caseSensitive, entireWord, again, previous. */
    find(term, options = {}) {
      bus.dispatch("find", {
        source: window,
        type: options.again ? "again" : "",
        query: term,
        caseSensitive: !!options.caseSensitive,
        entireWord: !!options.entireWord,
        highlightAll: true,
        findPrevious: !!options.previous,
        matchDiacritics: false,
      });
    },

    /** Chooses an annotation tool (pdf.js's AnnotationEditorType). */
    setTool(mode) {
      adapter.setTool(mode);
    },

    /** Zoom: "in", "out", "page-width", "page-fit", or a scale ("1.5"). */
    zoom(how) {
      adapter.zoom?.(how);
    },

    /** Scrolls to [page] (1-based). */
    scrollTo(page) {
      adapter.scrollTo?.(page);
    },
  };

  // Test hooks for the integration tests: they drive pdf.js's own editors
  // as a user would (no document content leaves the page).
  bridge.test = {
    adapter,
    get document() {
      return doc;
    },
    /** Selects the text of the first [chars] characters of a text layer. */
    selectText(pageNumber, chars) {
      const layer = document.querySelector(
        `.page[data-page-number="${pageNumber}"] .textLayer`,
      );
      if (!layer) return false;
      const walker = document.createTreeWalker(layer, NodeFilter.SHOW_TEXT);
      const first = walker.nextNode();
      if (!first) return false;
      let node = first;
      let left = chars;
      while (node && node.length < left) {
        left -= node.length;
        node = walker.nextNode() ?? node;
        if (left > 0 && node === first) break;
      }
      const range = document.createRange();
      range.setStart(first, 0);
      range.setEnd(node, Math.min(left, node.length));
      const selection = document.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
      document.dispatchEvent(new Event("selectionchange"));
      return true;
    },
    highlightSelection() {
      bus.dispatch("editingaction", {
        source: window,
        name: "highlightSelection",
      });
    },
    /** Pointer events on [pageNumber]'s editor layer, at fractions of it. */
    pointer(pageNumber, type, fx, fy) {
      const layer = document.querySelector(
        `.page[data-page-number="${pageNumber}"] .annotationEditorLayer`,
      );
      if (!layer) return false;
      const r = layer.getBoundingClientRect();
      const init = {
        bubbles: true,
        cancelable: true,
        composed: true,
        clientX: r.left + r.width * fx,
        clientY: r.top + r.height * fy,
        button: 0,
        buttons: type === "pointerup" ? 0 : 1,
        pointerId: 1,
        pointerType: "mouse",
        isPrimary: true,
      };
      // pdf.js acts only on events whose target is the layer itself
      // (pointerup reaches window by bubbling, as its drawing expects).
      layer.dispatchEvent(new PointerEvent(type, init));
      return true;
    },
    /** Types [text] into the free text editor being edited and commits it. */
    typeFreeText(text) {
      const div = document.querySelector(".freeTextEditor .internal");
      if (!div) return false;
      div.focus();
      div.textContent = text;
      div.dispatchEvent(new InputEvent("input", { bubbles: true }));
      div.blur();
      return true;
    },
    /** Sets a text form field (by its name) as typing would. */
    fillField(name, value) {
      const input = document.querySelector(
        `.annotationLayer [name="${CSS.escape(name)}"]`,
      );
      if (!input) return false;
      input.focus();
      input.value = value;
      input.dispatchEvent(new Event("input", { bubbles: true }));
      input.dispatchEvent(new Event("change", { bubbles: true }));
      input.blur();
      return true;
    },
    /** What the annotation storage holds, as `{count, types, fields}`. */
    storage() {
      const values = doc?.annotationStorage.serializable?.map;
      const types = [];
      if (values) {
        for (const v of values.values()) {
          if (v?.annotationType !== undefined) types.push(v.annotationType);
        }
      }
      return { count: doc?.annotationStorage.size ?? 0, types };
    },
  };

  window.forgeBridge = bridge;
  send({ type: "ready", mode: adapter.mode });
  return bridge;
}

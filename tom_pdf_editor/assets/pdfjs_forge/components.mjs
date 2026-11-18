// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

// The `components` mode: pdf.js's PDFViewer, PDFLinkService,
// PDFFindController and annotation editor in our own page.
import * as pdfjsLib from "../../build/pdf.mjs";
import { installBridge, trail } from "./bridge.mjs";

// pdf_viewer.mjs takes the library from the global.
globalThis.pdfjsLib = pdfjsLib;
const { EventBus, PDFLinkService, PDFFindController, PDFViewer } = await import(
  "../../components/pdf_viewer.mjs"
);

pdfjsLib.GlobalWorkerOptions.workerSrc = "../../build/pdf.worker.mjs";
const readOnly = new URLSearchParams(location.search).get("readonly") === "1";

const eventBus = new EventBus();
const linkService = new PDFLinkService({ eventBus });
const findController = new PDFFindController({ eventBus, linkService });
const container = document.getElementById("viewerContainer");
const pdfViewer = new PDFViewer({
  container,
  viewer: document.getElementById("viewer"),
  eventBus,
  linkService,
  findController,
  annotationMode: pdfjsLib.AnnotationMode.ENABLE_FORMS,
  annotationEditorMode: readOnly
    ? pdfjsLib.AnnotationEditorType.DISABLE
    : pdfjsLib.AnnotationEditorType.NONE,
  imageResourcesPath: "../../components/images/",
});
linkService.setViewer(pdfViewer);
// What the generic viewer's app does for its editor: mode changes the
// editor asks for (a highlight from the selection, Escape) reach the viewer.
eventBus.on("switchannotationeditormode", (e) => {
  pdfViewer.annotationEditorMode = e;
});
eventBus.on("showannotationeditorui", ({ mode }) => {
  pdfViewer.annotationEditorMode = { mode };
});
eventBus.on("pagesinit", () => {
  pdfViewer.currentScaleValue = "page-width";
});

let task = null;
let pdf = null;

const passwordForm = document.getElementById("password");
const passwordField = document.getElementById("passwordField");
function askPassword(update, reason) {
  document.getElementById("passwordLabel").textContent =
    reason === pdfjsLib.PasswordResponses.INCORRECT_PASSWORD
      ? "The password was wrong. Enter the password:"
      : "This PDF is protected. Enter its password:";
  passwordField.value = "";
  passwordForm.hidden = false;
  passwordField.focus();
  passwordForm.onsubmit = (e) => {
    e.preventDefault();
    passwordForm.hidden = true;
    update(passwordField.value);
    passwordField.value = "";
  };
  document.getElementById("passwordCancel").onclick = () => {
    passwordForm.hidden = true;
    task?.destroy();
  };
}

const ZOOMS = [0.5, 0.75, 1, 1.25, 1.5, 2, 3, 4];

installBridge({
  mode: "components",
  eventBus,
  async open(url, onPassword) {
    task = pdfjsLib.getDocument({
      url,
      cMapUrl: "../../web/cmaps/",
      cMapPacked: true,
      standardFontDataUrl: "../../web/standard_fonts/",
      wasmUrl: "../../web/wasm/",
      iccUrl: "../../web/iccs/",
      enableXfa: false,
      isEvalSupported: false,
    });
    task.onPassword = (update, reason) => {
      onPassword();
      askPassword(update, reason);
    };
    pdf = await task.promise;
    pdfViewer.setDocument(pdf);
    linkService.setDocument(pdf, null);
    return pdf;
  },
  async close() {
    passwordForm.hidden = true;
    const closing = task;
    task = null;
    pdf = null;
    pdfViewer.setDocument(null);
    linkService.setDocument(null, null);
    if (closing) await closing.destroy();
  },
  setTool(mode) {
    pdfViewer.annotationEditorMode = { mode };
  },
  zoom(how) {
    if (how === "in" || how === "out") {
      const now = pdfViewer.currentScale;
      const next =
        how === "in"
          ? ZOOMS.find((z) => z > now + 0.001) ?? ZOOMS.at(-1)
          : ZOOMS.findLast((z) => z < now - 0.001) ?? ZOOMS[0];
      pdfViewer.currentScale = next;
    } else {
      pdfViewer.currentScaleValue = how;
    }
  },
});
trail("components page ready");

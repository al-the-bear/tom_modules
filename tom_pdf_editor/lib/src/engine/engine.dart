// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The PDF engine as the editor sees it: [TomPdfEngine] and its value types.
/// Pure Dart; an engine package implements it (`PdfiumEngine` in
/// `tom_pdf_pdfium`, an isolate over FFI), the fake for tests is in
/// `testing.dart`.
///
/// Every position is in **view points**: points (1/72 inch) of the page as
/// it is shown (its rotation applied), origin at the top-left corner, y
/// downwards. The engine converts to and from PDF page space.
library;

import 'package:flutter/foundation.dart';

import 'annotation.dart';

export 'annotation.dart';

/// A rectangle in view points.
@immutable
final class PdfRect {
  /// A rectangle from its edges.
  const PdfRect(this.left, this.top, this.right, this.bottom);

  /// The left edge.
  final double left;

  /// The top edge.
  final double top;

  /// The right edge.
  final double right;

  /// The bottom edge.
  final double bottom;

  /// The width.
  double get width => right - left;

  /// The height.
  double get height => bottom - top;

  /// Whether ([x], [y]) lies inside.
  bool contains(double x, double y) =>
      x >= left && x <= right && y >= top && y <= bottom;

  @override
  bool operator ==(Object other) =>
      other is PdfRect &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'PdfRect($left, $top, $right, $bottom)';
}

/// A page's size in view points.
@immutable
final class PdfPageSize {
  /// A size from its parts.
  const PdfPageSize(this.width, this.height);

  /// The width.
  final double width;

  /// The height.
  final double height;

  @override
  bool operator ==(Object other) =>
      other is PdfPageSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);
}

/// One entry of the document's outline (bookmarks).
@immutable
final class PdfOutlineEntry {
  /// An entry from its parts.
  const PdfOutlineEntry(this.title, this.page, this.children);

  /// Its title.
  final String title;

  /// The page it leads to, or `null` when it names none.
  final int? page;

  /// Its children.
  final List<PdfOutlineEntry> children;
}

/// The permission bits of `FPDF_GetDocPermissions` the editor reads.
abstract final class PdfPermission {
  /// Bit 5: copy text and graphics.
  static const copy = 1 << 4;

  /// Bit 6: add or modify annotations, fill in form fields.
  static const annotate = 1 << 5;

  /// Bit 9: fill in form fields (also without [annotate]).
  static const fillForms = 1 << 8;
}

/// The form type (`FPDF_GetFormType`).
enum PdfFormType { none, acroForm, xfaFull, xfaForeground }

/// What an open document is.
@immutable
final class PdfDocumentInfo {
  /// A document from its parts.
  const PdfDocumentInfo({
    required this.handle,
    required this.pages,
    this.permissions = 0xFFFFFFFF,
    this.securityRevision = -1,
    this.fileVersion = 0,
    this.outline = const [],
    this.formType = PdfFormType.none,
  });

  /// The engine's handle for the document.
  final int handle;

  /// Every page's size, read without loading the pages.
  final List<PdfPageSize> pages;

  /// `FPDF_GetDocPermissions` (all bits set for an unencrypted file).
  final int permissions;

  /// `FPDF_GetSecurityHandlerRevision`: -1 when the file is not encrypted.
  final int securityRevision;

  /// `FPDF_GetFileVersion`, e.g. 17 for PDF 1.7.
  final int fileVersion;

  /// The outline, empty when there is none.
  final List<PdfOutlineEntry> outline;

  /// The form type.
  final PdfFormType formType;

  /// The page count.
  int get pageCount => pages.length;

  /// Whether the file is encrypted.
  bool get encrypted => securityRevision >= 0;

  /// Whether copying is allowed.
  bool get canCopy => permissions & PdfPermission.copy != 0;

  /// Whether annotating is allowed.
  bool get canAnnotate => permissions & PdfPermission.annotate != 0;

  /// Whether the permissions allow filling in form fields.
  bool get canFillForms =>
      permissions & (PdfPermission.annotate | PdfPermission.fillForms) != 0;
}

/// Why a document did not open.
enum PdfOpenError {
  /// A password is needed, or the one given is wrong (`FPDF_ERR_PASSWORD`).
  password,

  /// Not a PDF, or damaged beyond repair (`FPDF_ERR_FORMAT`).
  format,

  /// Not found or not readable (`FPDF_ERR_FILE`).
  file,

  /// An unsupported security scheme (`FPDF_ERR_SECURITY`).
  security,

  /// Any other failure.
  unknown,
}

/// The result of [TomPdfEngine.open].
@immutable
final class PdfOpenResult {
  /// An open document.
  const PdfOpenResult.opened(PdfDocumentInfo this.info)
    : error = null,
      message = null;

  /// A failure.
  const PdfOpenResult.failed(PdfOpenError this.error, this.message)
    : info = null;

  /// The document, when it opened.
  final PdfDocumentInfo? info;

  /// Why not.
  final PdfOpenError? error;

  /// The failure in words.
  final String? message;
}

/// How urgent a render is: visible tiles first, then thumbnails, then
/// prefetch.
enum PdfRenderPriority { visible, thumbnail, prefetch }

/// One rendered tile: BGRA pixels, `pxW × pxH × 4` bytes.
@immutable
final class PdfRendered {
  /// A tile from its parts.
  const PdfRendered(this.pxW, this.pxH, this.bgra);

  /// The width in pixels.
  final int pxW;

  /// The height in pixels.
  final int pxH;

  /// The pixels.
  final Uint8List bgra;
}

/// Text of a character range, and how many characters had no Unicode
/// mapping (skipped).
@immutable
final class PdfText {
  /// Text from its parts.
  const PdfText(this.text, this.skipped);

  /// The text.
  final String text;

  /// The characters left out (no Unicode mapping, or private use).
  final int skipped;
}

/// One search hit.
@immutable
final class PdfSearchHit {
  /// A hit from its parts.
  const PdfSearchHit(this.page, this.start, this.count, this.rects);

  /// The page.
  final int page;

  /// The first character's index on the page.
  final int start;

  /// The number of characters.
  final int count;

  /// Its rectangles, in view points.
  final List<PdfRect> rects;
}

/// A link's target.
@immutable
final class PdfLink {
  /// A link to a web address.
  const PdfLink.uri(String this.uri) : page = null;

  /// A link inside the document.
  const PdfLink.page(int this.page) : uri = null;

  /// The address, for a URI link.
  final String? uri;

  /// The page, for an internal link.
  final int? page;
}

/// The engine: one PDF library for every open document. Calls on one
/// document are answered in order; renders may be cancelled.
abstract interface class TomPdfEngine {
  /// Opens the file at [path] ([password] for an encrypted one). PDFium reads
  /// the file lazily, so a large file opens without being read into memory.
  Future<PdfOpenResult> open(String path, {String? password});

  /// Closes a document.
  Future<void> close(int doc);

  /// Renders the part of [page] that starts at ([x], [y]) pixels of the page
  /// rendered at [scale] pixels per point, [pxW] × [pxH] pixels, annotations
  /// and form fields included. `null` when [cancel]led before it ran.
  Future<PdfRendered?> render(
    int doc,
    int page, {
    required double scale,
    required int x,
    required int y,
    required int pxW,
    required int pxH,
    PdfRenderPriority priority = PdfRenderPriority.visible,
    int? ticket,
  });

  /// Drops a render request by the [ticket] it was sent with, if it has not
  /// run yet (it then answers `null`). A cancel of a render that has run, or
  /// is running, changes nothing and is not kept: a later render with the
  /// same ticket runs. Tickets name a request among all the engine's
  /// callers, so callers sharing an engine send distinct ones.
  void cancel(int ticket);

  /// The number of characters of [page] (0: no text layer).
  Future<int> charCount(int doc, int page);

  /// The character at ([x], [y]) on [page], within 5 points; -1 when none.
  Future<int> charIndexAt(int doc, int page, double x, double y);

  /// The rectangles of [count] characters from [start] on [page].
  Future<List<PdfRect>> rangeRects(int doc, int page, int start, int count);

  /// The text of [count] characters from [start] on [page].
  Future<PdfText> text(int doc, int page, int start, int count);

  /// Searches the document page by page, from [fromPage] round to the
  /// pages before it; hits stream back as they are found.
  Stream<PdfSearchHit> find(
    int doc,
    String term, {
    bool matchCase = false,
    bool wholeWord = false,
    int fromPage = 0,
  });

  /// The link at ([x], [y]) on [page], or `null`.
  Future<PdfLink?> linkAt(int doc, int page, double x, double y);

  /// The annotations of [page], in the file's order.
  Future<List<PdfAnnotation>> annotations(int doc, int page);

  /// Adds [annotation] to [page] as a PDF annotation (its `NM` is
  /// [PdfAnnotation.id]); answers it as the page now holds it.
  Future<PdfAnnotation> addAnnotation(
    int doc,
    int page,
    PdfAnnotation annotation,
  );

  /// Changes the annotation [match] (an `NM`, or `#<index>`) of [page] to
  /// [state]: rectangle, colour, quads, strokes, contents, `T`, `M`, and its
  /// `NM` becomes [PdfAnnotation.id].
  Future<void> updateAnnotation(
    int doc,
    int page,
    String match,
    PdfAnnotation state,
  );

  /// Removes the annotation [match] from [page].
  Future<void> removeAnnotation(int doc, int page, String match);

  /// Saves a full (not incremental) copy to [target]; [removeSecurity]
  /// writes it unencrypted. Returns an error message, or `null`.
  Future<String?> saveCopy(
    int doc,
    String target, {
    bool removeSecurity = false,
  });

  /// Saves the document incrementally to [target] (the original bytes stay
  /// a prefix), applying the cross-reference fix. Returns an error message,
  /// or `null` on success.
  Future<String?> saveIncremental(int doc, String target);

  /// Opens a document from its [bytes]: a file that has no path on this
  /// machine (a remote or virtual file system). Saves of such a document go
  /// through [saveIncrementalBytes].
  Future<PdfOpenResult> openBytes(Uint8List bytes, {String? password});

  /// Saves the document incrementally into memory, with the
  /// cross-reference fix; the original bytes stay a prefix. Throws when
  /// PDFium refuses.
  Future<Uint8List> saveIncrementalBytes(int doc);

  /// A full copy into memory; [removeSecurity] leaves the encryption out.
  Future<Uint8List> saveCopyBytes(int doc, {bool removeSecurity = false});

  // ------------------------------------------------------------------ forms

  /// The form fields (widgets) of [page].
  Future<List<PdfFormField>> formFields(int doc, int page);

  /// The form field at ([x], [y]) view points of [page], or `null`.
  Future<PdfFormField?> formFieldAt(int doc, int page, double x, double y);

  /// A click at ([x], [y]) view points of [page]: on a fillable field it
  /// goes to the form (focus, caret, a checkbox toggled); anywhere else the
  /// focused field loses its focus and the result is not [PdfFormResult.handled].
  Future<PdfFormResult> formClick(int doc, int page, double x, double y);

  /// Typed text for the focused field.
  Future<PdfFormResult> formText(int doc, String text);

  /// A key for the focused field.
  Future<PdfFormResult> formKey(int doc, PdfFormKey key, {bool shift = false});

  /// The focused field's own undo ([redo]: its redo) of the typing in it;
  /// not [PdfFormResult.handled] when it has none.
  Future<PdfFormResult> formUndo(int doc, {bool redo = false});

  /// Takes the focus from the focused field, committing its text.
  Future<PdfFormResult> formKillFocus(int doc);

  /// Sets a field's value (undo and redo of a [PdfFormChange]): [value] as
  /// [PdfFormChange] holds it.
  Future<PdfFormResult> formSetValue(
    int doc,
    int page,
    String name,
    PdfFieldType type,
    String value,
  );

  /// Gives up this user's share of the engine; the engine ends
  /// (`FPDF_DestroyLibrary`) when the last user has given up its share.
  Future<void> release();
}

/// The kinds of form fields.
enum PdfFieldType {
  /// Not known.
  unknown,

  /// A push button (not filled).
  pushButton,

  /// A checkbox.
  checkbox,

  /// A radio button.
  radio,

  /// A combo box (drawn, not filled in the prototype).
  comboBox,

  /// A list box (drawn, not filled in the prototype).
  listBox,

  /// A text field.
  text,

  /// A signature field (not filled).
  signature,
}

/// One widget of a form field.
@immutable
final class PdfFormField {
  /// A field from its parts.
  const PdfFormField({
    required this.page,
    required this.name,
    required this.index,
    required this.type,
    required this.rect,
    this.value = '',
    this.checked = false,
    this.readOnly = false,
  });

  /// From the wire form [toWire] gives.
  factory PdfFormField.fromWire(List<Object?> w) => PdfFormField(
    page: w[0]! as int,
    name: w[1]! as String,
    index: w[2]! as int,
    type: PdfFieldType.values[w[3]! as int],
    rect: PdfRect(
      (w[4]! as num).toDouble(),
      (w[5]! as num).toDouble(),
      (w[6]! as num).toDouble(),
      (w[7]! as num).toDouble(),
    ),
    value: w[8]! as String,
    checked: w[9]! as bool,
    readOnly: w[10]! as bool,
  );

  /// The page.
  final int page;

  /// The field's full name.
  final String name;

  /// Which of the page's widgets of this field it is (the buttons of a
  /// radio group), from 0.
  final int index;

  /// The type.
  final PdfFieldType type;

  /// The widget's rectangle, in view points.
  final PdfRect rect;

  /// The field's value.
  final String value;

  /// Whether a checkbox or radio button is on.
  final bool checked;

  /// Whether the field is read-only.
  final bool readOnly;

  /// Whether the editor fills it in: text fields, checkboxes and radio
  /// buttons that are not read-only.
  bool get fillable =>
      !readOnly &&
      (type == PdfFieldType.text ||
          type == PdfFieldType.checkbox ||
          type == PdfFieldType.radio);

  /// The wire form.
  List<Object?> toWire() => [
    page,
    name,
    index,
    type.index,
    rect.left,
    rect.top,
    rect.right,
    rect.bottom,
    value,
    checked,
    readOnly,
  ];

  @override
  String toString() =>
      'PdfFormField(${type.name} $name#$index p$page "$value"${checked ? ' on' : ''})';
}

/// A committed change of one field: a text field's text (committed when it
/// loses the focus), a checkbox turned on or off (`on` / `off`), the button of
/// a radio group that is on (its widget index, `''` for none).
@immutable
final class PdfFormChange {
  /// A change from its parts.
  const PdfFormChange(this.page, this.name, this.type, this.before, this.after);

  /// From the wire form [toWire] gives.
  factory PdfFormChange.fromWire(List<Object?> w) => PdfFormChange(
    w[0]! as int,
    w[1]! as String,
    PdfFieldType.values[w[2]! as int],
    w[3]! as String,
    w[4]! as String,
  );

  /// The page.
  final int page;

  /// The field's full name.
  final String name;

  /// The type.
  final PdfFieldType type;

  /// The value before.
  final String before;

  /// The value after.
  final String after;

  /// The wire form.
  List<Object?> toWire() => [page, name, type.index, before, after];

  @override
  bool operator ==(Object other) =>
      other is PdfFormChange &&
      other.page == page &&
      other.name == name &&
      other.type == type &&
      other.before == before &&
      other.after == after;

  @override
  int get hashCode => Object.hash(page, name, type, before, after);

  @override
  String toString() => 'PdfFormChange(p$page $name: "$before" → "$after")';
}

/// What a form call did.
@immutable
final class PdfFormResult {
  /// A result from its parts.
  const PdfFormResult({
    this.handled = false,
    this.dirtyPages = const {},
    this.focused,
    this.changes = const [],
  });

  /// From the wire form [toWire] gives.
  factory PdfFormResult.fromWire(List<Object?> w) => PdfFormResult(
    handled: w[0]! as bool,
    dirtyPages: {for (final p in w[1]! as List) p as int},
    focused: w[2] == null
        ? null
        : PdfFormField.fromWire(w[2]! as List<Object?>),
    changes: [
      for (final c in w[3]! as List) PdfFormChange.fromWire(c as List<Object?>),
    ],
  );

  /// Whether the form took the input.
  final bool handled;

  /// The pages whose appearance changed (to render again).
  final Set<int> dirtyPages;

  /// The field that has the focus afterwards.
  final PdfFormField? focused;

  /// The changes committed by the call (each one history entry).
  final List<PdfFormChange> changes;

  /// The wire form.
  List<Object?> toWire() => [
    handled,
    dirtyPages.toList(),
    focused?.toWire(),
    [for (final c in changes) c.toWire()],
  ];
}

/// The keys a focused field takes besides typed text.
enum PdfFormKey {
  /// Backspace.
  backspace,

  /// Forward delete.
  delete,

  /// Left arrow.
  left,

  /// Right arrow.
  right,

  /// Up arrow.
  up,

  /// Down arrow.
  down,

  /// Home.
  home,

  /// End.
  end,

  /// Return (a new line in a multi-line field).
  enter,

  /// Tab: the next field (Shift: the previous).
  tab,

  /// Select all.
  selectAll,
}

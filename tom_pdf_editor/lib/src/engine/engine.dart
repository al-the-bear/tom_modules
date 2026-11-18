// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The PDF engine as the editor sees it: [TomPdfEngine] and its value types.
/// Pure Dart; the PDFium implementation (`PdfiumEngine`, an isolate over
/// FFI) is in `pdfium.dart`, the fake for tests in `testing.dart`.
///
/// Every position is in **view points**: points (1/72 inch) of the page as
/// it is shown (its rotation applied), origin at the top-left corner, y
/// downwards. The engine converts to and from PDF page space.
library;

import 'package:flutter/foundation.dart';

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
  /// run yet.
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

  /// Saves the document incrementally to [target] (the original bytes stay
  /// a prefix), applying the cross-reference fix. Returns an error message,
  /// or `null` on success.
  Future<String?> saveIncremental(int doc, String target);

  /// Gives up this user's share of the engine; the engine ends
  /// (`FPDF_DestroyLibrary`) when the last user has given up its share.
  Future<void> release();
}

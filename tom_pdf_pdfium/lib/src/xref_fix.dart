// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The cross-reference fix (WD `part-pdf-pdfium`, *Saving*). PDFium
/// 159.0.8152.0's incremental save appends a cross-reference stream without
/// `/Type /XRef` when the original uses cross-reference streams; PDFium,
/// Chrome and pdf.js accept it, but macOS (PDFKit, so Preview) refuses the
/// file. The fix inserts `/Type/XRef ` right after the stream dictionary's
/// `<<`. Nothing the file records points behind that place (the object's own
/// offset is before it; `startxref` and `%%EOF` follow the object and are
/// not offsets), so no offset moves.
library;

import 'dart:convert';
import 'dart:typed_data';

/// What is inserted.
const kXrefTypeEntry = '/Type/XRef ';

/// The offset `startxref` names, read from the file's [tail] (its last
/// bytes); `null` when there is none.
int? startxrefOffset(Uint8List tail) {
  final text = latin1.decode(tail);
  final at = text.lastIndexOf('startxref');
  if (at < 0) return null;
  final match = RegExp(r'^startxref\s+(\d+)').firstMatch(text.substring(at));
  return match == null ? null : int.tryParse(match[1]!);
}

/// Where `/Type/XRef ` belongs in [object] (the bytes from the offset
/// `startxref` names to the end of the file): right after the stream
/// dictionary's `<<`. `null` when nothing is to be done: the object is a
/// classic `xref` table, not a cross-reference stream, or its dictionary
/// already has a `/Type`.
int? xrefTypeInsertionPoint(Uint8List object) {
  // Enough to hold the object header and its dictionary.
  final head = latin1.decode(
    Uint8List.sublistView(object, 0, object.length.clamp(0, 64 * 1024)),
  );
  final header = RegExp(r'^\s*\d+\s+\d+\s+obj\s*<<').firstMatch(head);
  if (header == null) return null; // `xref` table, or not an object
  final dictStart = header.end; // just after `<<`
  final streamAt = head.indexOf(RegExp(r'>>\s*stream'), dictStart);
  if (streamAt < 0) return null; // not a stream object
  final dict = head.substring(dictStart, streamAt);
  if (!dict.contains('/W')) return null; // not a cross-reference stream
  if (RegExp(r'/Type[\s/]').hasMatch(dict)) return null; // has its /Type
  return dictStart;
}

/// [object] with `/Type/XRef ` inserted where [xrefTypeInsertionPoint] says,
/// or `null` when nothing is to be done.
Uint8List? fixXrefObject(Uint8List object) {
  final at = xrefTypeInsertionPoint(object);
  if (at == null) return null;
  return Uint8List.fromList([
    ...object.sublist(0, at),
    ...latin1.encode(kXrefTypeEntry),
    ...object.sublist(at),
  ]);
}

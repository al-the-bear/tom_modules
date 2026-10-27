/// Structural rewriting of formula references.
///
/// A reference is moved by parsing the formula, replacing the node and
/// printing it again. Doing it on the string would also rewrite the `A1`
/// inside `"see A1"`.
library;

import 'cells.dart';
import 'formula_engine.dart';

/// Where one reference of a formula should point after a rewrite.
///
/// Returns the node to put in its place. Returning the node it was given
/// leaves the reference alone.
typedef FormulaReferenceRewrite = FormulaNode Function(FormulaNode reference);

/// [formula] with every cell and range reference passed through [rewrite].
///
/// A formula that does not parse is returned **unchanged**: it already
/// evaluates to `#ERROR!`, and a rewrite that cannot read it has nothing it
/// could correctly move.
String rewriteFormulaReferences(
  String formula,
  FormulaReferenceRewrite rewrite,
) {
  final FormulaNode ast;
  try {
    ast = FormulaParser.parse(formula);
  } on FormatException {
    return formula;
  }
  return formulaSource(_map(ast, rewrite));
}

/// Every cell and range reference in [formula], in source order. Empty for a
/// formula that does not parse.
List<FormulaNode> formulaReferences(String formula) {
  final out = <FormulaNode>[];
  try {
    _map(FormulaParser.parse(formula), (reference) {
      out.add(reference);
      return reference;
    });
  } on FormatException {
    return const [];
  }
  return out;
}

FormulaNode _map(FormulaNode node, FormulaReferenceRewrite rewrite) =>
    switch (node) {
      CellReference() || RangeReference() => rewrite(node),
      UnaryOp(:final op, :final operand) => UnaryOp(op, _map(operand, rewrite)),
      BinaryOp(:final op, :final left, :final right) => BinaryOp(
        op,
        _map(left, rewrite),
        _map(right, rewrite),
      ),
      FunctionCall(:final name, :final arguments) => FunctionCall(name, [
        for (final a in arguments) _map(a, rewrite),
      ]),
      _ => node,
    };

/// A rectangle of cells, inclusive at both corners.
class CellRect {
  final CellAddress topLeft;
  final CellAddress bottomRight;

  CellRect(CellAddress a, CellAddress b)
    : topLeft = CellAddress(
        a.column < b.column ? a.column : b.column,
        a.row < b.row ? a.row : b.row,
      ),
      bottomRight = CellAddress(
        a.column > b.column ? a.column : b.column,
        a.row > b.row ? a.row : b.row,
      );

  /// Parses `B2:C4`, or a single `B2`.
  static CellRect parse(String text) {
    final parts = text.trim().toUpperCase().split(':');
    if (parts.length > 2) {
      throw FormatException('Not a cell range: "$text"');
    }
    final first = CellAddress.parse(parts.first);
    return CellRect(
      first,
      parts.length == 2 ? CellAddress.parse(parts.last) : first,
    );
  }

  int get width => bottomRight.column - topLeft.column + 1;
  int get height => bottomRight.row - topLeft.row + 1;

  bool contains(CellAddress address) =>
      address.column >= topLeft.column &&
      address.column <= bottomRight.column &&
      address.row >= topLeft.row &&
      address.row <= bottomRight.row;

  bool containsRect(CellAddress a, CellAddress b) => contains(a) && contains(b);

  bool overlaps(CellAddress a, CellAddress b) {
    final other = CellRect(a, b);
    return other.topLeft.column <= bottomRight.column &&
        other.bottomRight.column >= topLeft.column &&
        other.topLeft.row <= bottomRight.row &&
        other.bottomRight.row >= topLeft.row;
  }

  /// [address] moved by the offset that takes [topLeft] to [to].
  CellAddress rebase(CellAddress address, CellAddress to) => CellAddress(
    address.column - topLeft.column + to.column,
    address.row - topLeft.row + to.row,
  );

  String encode() => topLeft == bottomRight
      ? topLeft.encode()
      : '${topLeft.encode()}:${bottomRight.encode()}';

  @override
  String toString() => encode();
}

/// [reference] pointing at the same cells after they moved from [from] (whose
/// top-left lands on [to]) into the sheet named [sheet] — null for the
/// formula's own sheet.
FormulaNode moveFormulaReference(
  FormulaNode reference, {
  required CellRect from,
  required CellAddress to,
  required String? sheet,
}) => switch (reference) {
  CellReference() => CellReference(
    from.rebase(reference.address, to),
    absoluteColumn: reference.absoluteColumn,
    absoluteRow: reference.absoluteRow,
    sheet: sheet,
  ),
  RangeReference() => RangeReference(
    from.rebase(reference.start, to),
    from.rebase(reference.end, to),
    startAbsoluteColumn: reference.startAbsoluteColumn,
    startAbsoluteRow: reference.startAbsoluteRow,
    endAbsoluteColumn: reference.endAbsoluteColumn,
    endAbsoluteRow: reference.endAbsoluteRow,
    sheet: sheet,
  ),
  _ => reference,
};

/// [reference] unchanged in address, in the sheet named [sheet].
FormulaNode formulaReferenceInSheet(FormulaNode reference, String? sheet) =>
    switch (reference) {
      CellReference() => CellReference(
        reference.address,
        absoluteColumn: reference.absoluteColumn,
        absoluteRow: reference.absoluteRow,
        sheet: sheet,
      ),
      RangeReference() => RangeReference(
        reference.start,
        reference.end,
        startAbsoluteColumn: reference.startAbsoluteColumn,
        startAbsoluteRow: reference.startAbsoluteRow,
        endAbsoluteColumn: reference.endAbsoluteColumn,
        endAbsoluteRow: reference.endAbsoluteRow,
        sheet: sheet,
      ),
      _ => reference,
    };

/// How a formula reaches another sheet: the reference port.
///
/// A formula may read a cell of another sheet by writing a quoted reference
/// before it — `'#budget'!B2`. What the quoted string names, and where that
/// sheet's cells come from, is the application's: it implements
/// [FormulaReferenceResolver], and the engine asks it.
library;

import 'cells.dart';

/// What a reference names, before anything is read: the identity of the sheet
/// and whether the reference is written as local to the sheet holding it.
///
/// The engine indexes a formula's reads of other sheets by [id], so an edit in
/// that sheet finds its readers under one key however each reader spelled the
/// reference. A [local] reference to the holder's own id is a read of the
/// holder itself.
final class FormulaSheetName {
  final String id;
  final bool local;

  const FormulaSheetName(this.id, {required this.local});
}

/// A sheet a reference resolved to.
final class FormulaSheetTarget {
  /// The sheet's identity — the same [FormulaSheetName.id] the reference named.
  final String id;

  /// How references written **inside** the target resolve. A reference is
  /// relative to the sheet that holds it, so a chain of references is
  /// resolved hop by hop, each through its own holder's resolver.
  final FormulaReferenceResolver references;

  final Map<CellAddress, FormulaCell>? Function() _cells;

  /// [cells] is called at most once per recalculation and answers the
  /// target's cells, or null when they cannot be read — every cell of the
  /// target then reads `#REF!`.
  const FormulaSheetTarget({
    required this.id,
    required this.references,
    required Map<CellAddress, FormulaCell>? Function() cells,
  }) : _cells = cells;

  /// The target's cells, or null when they cannot be read.
  Map<CellAddress, FormulaCell>? readCells() => _cells();
}

/// Resolves the quoted references formulas write.
abstract interface class FormulaReferenceResolver {
  /// What [reference] names, or null when it is not a reference at all (it
  /// then reads `#REF!` and makes the formula depend on nothing).
  FormulaSheetName? nameOf(String reference);

  /// The sheet [reference] names, or null when it names nothing that is a
  /// sheet — every cell read through it is then `#REF!`.
  FormulaSheetTarget? resolve(String reference);
}

/// The resolver for a sheet that reaches no other sheet: every reference is
/// `#REF!`.
final class FormulaNoReferences implements FormulaReferenceResolver {
  const FormulaNoReferences();

  @override
  FormulaSheetName? nameOf(String reference) => null;

  @override
  FormulaSheetTarget? resolve(String reference) => null;
}

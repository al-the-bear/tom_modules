/// The evaluation port, and the native backend that is its default.
///
/// The recalculation scheduler (`SheetEngine`) owns the dependency
/// graph and the order, and calls [FormulaEvaluationBackend.evaluate] once per
/// formula cell. A backend never schedules, never walks dependencies and never
/// writes. Two exist: [NativeFormulaBackend] here, which walks the AST, and
/// an interpreting backend in a package that may name an interpreter, which
/// interprets the lowered expression — kept out of this package so that the
/// engine, and everything that
/// reuses it, never links an interpreter.
library;

import 'cells.dart';
import 'formula_engine.dart';
import 'formula_lowering.dart';
import 'formula_value.dart';

/// One formula, as a backend receives it: the source, its AST, and — on
/// demand — the memoised lowered expression.
///
/// The AST is parsed once by the scheduler, which needed it for dependency
/// extraction anyway (extraction runs on the AST, before lowering). The
/// lowered string is computed only when a backend asks, so the native backend
/// never forces lowering.
final class FormulaProgram {
  /// The `=…` source the formula bar shows.
  final String source;

  /// The AST of [source].
  final FormulaNode ast;

  final FormulaLowering _lowering;

  FormulaProgram(this.source, this.ast, {FormulaLowering? lowering})
    : _lowering = lowering ?? formulaLowering;

  /// The lowered Dart expression, through the memo.
  ///
  /// Never null for a program: a program exists only for a source that
  /// parsed, and lowering is total over parsed sources.
  String get lowered => _lowering.lower(source)!;
}

/// What a backend evaluates against: the formula's own sheet, and the
/// resolver behind `formula.sheet(…)`.
///
/// `currentSheet` **is** the identifier resolver — an A1 identifier
/// resolves to a cell of it — which is why the context carries the sheet rather
/// than a second, string-keyed lookup that would say the same thing.
///
/// Both sheets are read-only: [FormulaSheet] has no writer.
final class FormulaEvaluationContext {
  /// The sheet the formula lives in. `cell` is a **scalar** read — an embedded
  /// cell answers `#VALUE!` — and `range` keeps every value, the
  /// embedded sentinel included, for an aggregate to skip.
  final FormulaSheet currentSheet;

  /// The sheet a unified reference names. Never throws: a reference
  /// that does not resolve to a spreadsheet answers a sheet every cell of
  /// which is `#REF!`.
  final FormulaSheet Function(String unifiedReference) sheet;

  const FormulaEvaluationContext({
    required this.currentSheet,
    required this.sheet,
  });
}

/// The port.
abstract interface class FormulaEvaluationBackend {
  /// Stable identifier for settings and diagnostics: `native` or `d4rt`.
  String get id;

  /// Evaluates one formula in one cell context. MUST NOT mutate anything.
  FormulaValue evaluate(
    FormulaProgram program,
    FormulaEvaluationContext context,
  );
}

/// The default backend in 1.0: walks the AST and calls the shared
/// function library directly. Defines the formula semantics — a disagreement with
/// any other backend is that backend's failure.
final class NativeFormulaBackend implements FormulaEvaluationBackend {
  const NativeFormulaBackend();

  static const backendId = 'native';

  @override
  String get id => backendId;

  @override
  FormulaValue evaluate(
    FormulaProgram program,
    FormulaEvaluationContext context,
  ) => FormulaEvaluator(context).evaluate(program.ast);
}

/// The process's backend. Exactly one is active, chosen at
/// composition time with [useFormulaBackend]; native until then.
FormulaEvaluationBackend get formulaBackend => _active;

FormulaEvaluationBackend _active = const NativeFormulaBackend();

/// Makes [backend] the process's backend.
///
/// For a composition root, before the first sheet is evaluated: a sheet keeps
/// the backend it was built with, so switching later would leave two answering
/// at once.
void useFormulaBackend(FormulaEvaluationBackend backend) {
  _active = backend;
}

/// A [FormulaSheet] over a raw cell lookup — 1-based A1 addresses in,
/// values out.
///
/// The one place a cell read becomes a **scalar** read: an embedded cell is
/// `#VALUE!` through [cell] and stays the sentinel through [range].
/// Both backends read cells only through a sheet, so the rule cannot be
/// applied by one and forgotten by the other.
final class FormulaLookupSheet implements FormulaSheet {
  final FormulaValue Function(CellAddress address) _lookup;

  const FormulaLookupSheet(this._lookup);

  @override
  FormulaValue cell(int row, int column) =>
      formulaScalarCellValue(_lookup(CellAddress(column, row + 1)));

  @override
  FormulaValue range(
    int topRow,
    int leftColumn,
    int bottomRow,
    int rightColumn,
  ) => FormulaRange([
    for (var r = topRow; r <= bottomRow; r++)
      for (var c = leftColumn; c <= rightColumn; c++)
        _lookup(CellAddress(c, r + 1)),
  ]);
}

/// A sheet every cell of which is `#REF!` — the answer for a reference
/// that names no spreadsheet.
final class FormulaUnresolvedSheet implements FormulaSheet {
  const FormulaUnresolvedSheet();

  @override
  FormulaValue cell(int row, int column) => FormulaError.ref;

  @override
  FormulaValue range(
    int topRow,
    int leftColumn,
    int bottomRow,
    int rightColumn,
  ) => FormulaError.ref;
}

/// A cell's value read as a scalar: an embedded cell is `#VALUE!`.
FormulaValue formulaScalarCellValue(FormulaValue value) =>
    value is FormulaEmbedded ? FormulaError.value : value;

/// What a formula's result becomes as a **cell's** value.
///
/// A range is only ever an argument: a formula whose result is one — `=A1:A3`,
/// or an `IF` that picked a range — is `#VALUE!` in its cell. Applied by the
/// scheduler to whatever a backend returns, so it is one rule over both.
FormulaValue formulaCellResult(FormulaValue value) => switch (value) {
  FormulaRange() || FormulaEmbedded() => FormulaError.value,
  FormulaNumber() ||
  FormulaText() ||
  FormulaBoolean() ||
  FormulaBlank() ||
  FormulaError() => value,
};

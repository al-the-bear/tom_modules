/// The differential corpus, loaded, with the fixture every case runs in.
library;

import '../cells.dart';
import '../formula_backend.dart';
import '../formula_engine.dart';
import '../formula_value.dart';
import '../references.dart';
import 'corpus_data.dart';

/// One row of the corpus.
final class FormulaCorpusCase {
  final String id;

  /// The class the row belongs to: `catalog`, `operator`, `error`,
  /// `coercion`, `section`, `reference` or `short-circuit`.
  final String cls;

  /// For an `error` row: whether the error `originates` or `propagates`.
  final String? kind;

  final String? formula;

  /// The cell [formula] is written into.
  final String target;

  /// The row's own cells, merged over the corpus base.
  final Map<CellAddress, FormulaCell> cells;

  final FormulaValue expected;

  const FormulaCorpusCase({
    required this.id,
    required this.cls,
    required this.kind,
    required this.formula,
    required this.target,
    required this.cells,
    required this.expected,
  });
}

/// The corpus ([formulaCorpusData]), parsed.
final class FormulaCorpus {
  final Map<CellAddress, FormulaCell> base;
  final Map<CellAddress, FormulaCell> other;
  final Map<CellAddress, FormulaCell> ext;
  final List<FormulaCorpusCase> cases;

  FormulaCorpus._(this.base, this.other, this.ext, this.cases);

  /// The corpus this package carries.
  factory FormulaCorpus.load() {
    final raw = formulaCorpusData;
    return FormulaCorpus._(
      _cells(raw['base']),
      _cells(raw['other']),
      _cells(raw['ext']),
      [
        for (final row in raw['cases']! as List)
          _case((row as Map).cast<String, Object?>()),
      ],
    );
  }

  /// [row] evaluated by [backend] through the real scheduler — the computed
  /// value of its target cell.
  FormulaValue evaluate(
    FormulaCorpusCase row,
    FormulaEvaluationBackend backend,
  ) {
    final main = {
      ...base,
      ...row.cells,
      if (row.formula != null)
        CellAddress.parse(row.target): FormulaCell.formula(row.formula!),
    };
    final engine = SheetEngine(
      main,
      selfId: _main,
      references: _Fixture(this, local: true),
      backend: backend,
    );
    return engine.valueOf(CellAddress.parse(row.target));
  }

  static FormulaCorpusCase _case(Map<String, Object?> row) {
    final formula = row['formula'] as String?;
    return FormulaCorpusCase(
      id: row['id']! as String,
      cls: row['class']! as String,
      kind: row['kind'] as String?,
      formula: formula == null ? null : _substitute(formula),
      target: (row['target'] as String?) ?? 'Z1',
      cells: _cells(row['cells']),
      expected: _expected((row['expected']! as Map).cast<String, Object?>()),
    );
  }

  static Map<CellAddress, FormulaCell> _cells(Object? value) {
    if (value == null) return {};
    return {
      for (final MapEntry(:key, :value) in (value as Map).entries)
        CellAddress.parse(key as String): _cell(
          (value as Map).cast<String, Object?>(),
        ),
    };
  }

  static FormulaCell _cell(Map<String, Object?> map) =>
      switch (map.keys.single) {
        'formula' => FormulaCell.formula(
          _substitute(map['formula']! as String),
        ),
        r'$ref' => FormulaCell.embedded(_substitute(map[r'$ref']! as String)),
        _ => FormulaCell.value(map['value']),
      };

  static FormulaValue _expected(Map<String, Object?> spec) {
    if (spec.length != 1) {
      throw FormatException('An expected value has exactly one key: $spec');
    }
    final MapEntry(:key, :value) = spec.entries.single;
    return switch (key) {
      'number' => FormulaNumber(value! as num),
      'text' => FormulaText(value! as String),
      'boolean' => FormulaBoolean(value! as bool),
      'blank' => FormulaBlank.instance,
      'error' => FormulaError(FormulaErrorCode.fromToken(value! as String)!),
      _ => throw FormatException('Unknown expected kind "$key"'),
    };
  }
}

const _main = 'main';
const _other = 'other';
const _prose = 'prose';
const _ext = 'ext';
const _missing = 'missing';

/// `ext` lives in another container: a reference to it is not local.
const _extReference = 'book#$_ext';

String _substitute(String text) => text
    .replaceAll('{other}', _other)
    .replaceAll('{prose}', _prose)
    .replaceAll('{ext}', _extReference)
    .replaceAll('{missing}', _missing);

/// The corpus's references: `main` and `other` side by side, `prose` that is
/// not a sheet, `ext` in another container, `missing` nowhere.
final class _Fixture implements FormulaReferenceResolver {
  _Fixture(this.corpus, {required this.local});

  final FormulaCorpus corpus;

  /// Whether the references are written in `main`'s container.
  final bool local;

  @override
  FormulaSheetName? nameOf(String reference) {
    if (reference == _extReference) {
      return const FormulaSheetName(_ext, local: false);
    }
    if (reference.isEmpty || reference.contains('#')) return null;
    return FormulaSheetName(reference, local: local);
  }

  @override
  FormulaSheetTarget? resolve(String reference) {
    final name = nameOf(reference);
    if (name == null) return null;
    return switch (name.id) {
      _other when name.local => FormulaSheetTarget(
        id: _other,
        references: this,
        cells: () => corpus.other,
      ),
      _ext => FormulaSheetTarget(
        id: _ext,
        references: _Fixture(corpus, local: false),
        cells: () => corpus.ext,
      ),
      _ => null,
    };
  }
}

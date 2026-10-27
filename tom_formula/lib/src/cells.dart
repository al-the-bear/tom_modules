/// The grid a formula engine computes over: addresses and cells.
library;

/// What a cell holds — exactly one of these.
enum FormulaCellKind {
  /// A literal: a number, a string, a boolean, or nothing.
  value,

  /// A formula, with its leading `=`.
  formula,

  /// Something the application embeds in the cell — a document, an image, a
  /// nested sheet. It has no scalar value: a scalar read of it is `#VALUE!`
  /// and an aggregate over a range skips it.
  embedded,
}

/// A cell address like `B12`: column letters and a 1-based row.
class CellAddress implements Comparable<CellAddress> {
  /// 0-based column index (`A` = 0, `Z` = 25, `AA` = 26, …).
  final int column;

  /// 1-based row number, as written in the address.
  final int row;

  const CellAddress(this.column, this.row);

  /// Parses an `A1`-style address. Throws [FormatException] on anything else.
  static CellAddress parse(String address) {
    final match = _pattern.firstMatch(address);
    if (match == null) {
      throw FormatException('Not a cell address: "$address"');
    }
    return CellAddress(
      columnIndexFromLetters(match.group(1)!),
      int.parse(match.group(2)!),
    );
  }

  static final _pattern = RegExp(r'^([A-Z]+)([1-9][0-9]*)$');

  static int columnIndexFromLetters(String letters) {
    var index = 0;
    for (final unit in letters.codeUnits) {
      index = index * 26 + (unit - 0x41 + 1);
    }
    return index - 1;
  }

  static String lettersFromColumnIndex(int index) {
    var n = index + 1;
    final buffer = StringBuffer();
    while (n > 0) {
      n--;
      buffer.writeCharCode(0x41 + n % 26);
      n ~/= 26;
    }
    return String.fromCharCodes(buffer.toString().codeUnits.reversed);
  }

  String encode() => '${lettersFromColumnIndex(column)}$row';

  @override
  int compareTo(CellAddress other) =>
      column != other.column ? column - other.column : row - other.row;

  @override
  bool operator ==(Object other) =>
      other is CellAddress && other.column == column && other.row == row;

  @override
  int get hashCode => Object.hash(column, row);

  @override
  String toString() => encode();
}

/// One cell — exactly one of a literal [value], a [formula], or an
/// [embedded] object the application owns.
class FormulaCell {
  /// The literal: a number, a string, a boolean, or null.
  final Object? value;

  /// The formula, with its leading `=`.
  final String? formula;

  /// What the application embedded. The engine never looks inside it; it is
  /// compared with `==` to decide whether a cell changed.
  final Object? embedded;

  const FormulaCell.value(this.value) : formula = null, embedded = null;

  /// Throws [FormatException] when [formula] does not start with `=`.
  FormulaCell.formula(String this.formula) : value = null, embedded = null {
    if (!formula!.startsWith('=')) {
      throw FormatException('Formula must start with "=": "$formula"');
    }
  }

  const FormulaCell.embedded(Object this.embedded)
    : value = null,
      formula = null;

  FormulaCellKind get kind => formula != null
      ? FormulaCellKind.formula
      : embedded != null
      ? FormulaCellKind.embedded
      : FormulaCellKind.value;

  /// Whether [other] holds the same thing — the literal's type included, so
  /// `1` and `1.0` differ, and an embedded object by `==`.
  bool sameAs(FormulaCell? other) {
    if (other == null || kind != other.kind) return false;
    return switch (kind) {
      FormulaCellKind.value =>
        value == other.value && value.runtimeType == other.value.runtimeType,
      FormulaCellKind.formula => formula == other.formula,
      FormulaCellKind.embedded => embedded == other.embedded,
    };
  }

  @override
  String toString() => switch (kind) {
    FormulaCellKind.value => 'FormulaCell.value($value)',
    FormulaCellKind.formula => 'FormulaCell.formula($formula)',
    FormulaCellKind.embedded => 'FormulaCell.embedded($embedded)',
  };
}

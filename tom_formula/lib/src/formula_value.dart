/// The formula value model — a **sealed** type.
///
/// Every catalog function, every operator and the engine compute over
/// [FormulaValue]. Two properties are why it is sealed rather than `Object?`:
///
/// * a coercion helper is an exhaustive `switch`, so a later variant cannot be
///   forgotten by one of them — the compiler names the helper that missed it;
/// * the embedded-cell sentinel is a variant of its own,
///   [FormulaEmbedded], rather than a class carried alongside `Object?`, so
///   "an embedded cell" can never be confused with a computed
///   `#VALUE!`.
///
/// Errors are **values**, not exceptions and not strings: they
/// propagate through every consuming formula without aborting the rest of a
/// recalculation, and `#VALUE!` as a value can never collide with a cell whose
/// literal text happens to be `#VALUE!`.
library;

/// A value a formula computes or reads.
sealed class FormulaValue {
  const FormulaValue();

  /// The value as the cell displays it: whole doubles as integers,
  /// booleans as `TRUE`/`FALSE`, an error as its token, a blank as
  /// nothing.
  String get display;
}

final class FormulaNumber extends FormulaValue {
  final num value;
  const FormulaNumber(this.value);

  @override
  String get display =>
      value is double && value == value.roundToDouble() && value.isFinite
      ? value.toInt().toString()
      : value.toString();

  @override
  bool operator ==(Object other) =>
      other is FormulaNumber && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => display;
}

final class FormulaText extends FormulaValue {
  final String value;
  const FormulaText(this.value);

  @override
  String get display => value;

  @override
  bool operator ==(Object other) =>
      other is FormulaText && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

final class FormulaBoolean extends FormulaValue {
  final bool value;
  const FormulaBoolean(this.value);

  static const yes = FormulaBoolean(true);
  static const no = FormulaBoolean(false);

  @override
  String get display => value ? 'TRUE' : 'FALSE';

  @override
  bool operator ==(Object other) =>
      other is FormulaBoolean && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => display;
}

/// An empty cell: `0` in numeric context and `""` in text context.
final class FormulaBlank extends FormulaValue {
  const FormulaBlank._();

  static const instance = FormulaBlank._();

  @override
  String get display => '';

  @override
  String toString() => '';
}

/// An embedded cell. Not a value: a scalar read of
/// it is `#VALUE!`, an aggregate over a range skips it.
final class FormulaEmbedded extends FormulaValue {
  const FormulaEmbedded._();

  static const instance = FormulaEmbedded._();

  @override
  String get display => '';

  @override
  String toString() => '#EMBEDDED';
}

/// A range's values, row-major — the argument form of a range reference.
///
/// Only ever an **argument**: a bare range in scalar position is `#VALUE!`,
/// so no cell's computed value is ever a [FormulaRange].
final class FormulaRange extends FormulaValue {
  final List<FormulaValue> values;
  const FormulaRange(this.values);

  @override
  String get display => const FormulaError(FormulaErrorCode.value).display;

  @override
  bool operator ==(Object other) =>
      other is FormulaRange &&
      other.values.length == values.length &&
      Iterable<int>.generate(
        values.length,
      ).every((i) => other.values[i] == values[i]);

  @override
  int get hashCode => Object.hashAll(values);

  @override
  String toString() => values.toString();
}

/// The error codes, each with its token.
///
/// **The one place the tokens are written**. Everything that prints
/// or parses an error — the display form, the `#REF!` literal a structural
/// rewrite writes into a formula, the grammar that reads it back — goes
/// through [token] and [fromToken].
enum FormulaErrorCode {
  divideByZero('#DIV/0!'),
  value('#VALUE!'),
  ref('#REF!'),
  name('#NAME?'),
  cycle('#CYCLE!'),
  syntax('#ERROR!');

  const FormulaErrorCode(this.token);

  final String token;

  /// The code whose token is [token], or null.
  static FormulaErrorCode? fromToken(String token) {
    for (final code in values) {
      if (code.token == token) return code;
    }
    return null;
  }
}

final class FormulaError extends FormulaValue {
  final FormulaErrorCode code;
  const FormulaError(this.code);

  static const div0 = FormulaError(FormulaErrorCode.divideByZero);
  static const value = FormulaError(FormulaErrorCode.value);
  static const ref = FormulaError(FormulaErrorCode.ref);
  static const cycle = FormulaError(FormulaErrorCode.cycle);
  static const name = FormulaError(FormulaErrorCode.name);
  static const generic = FormulaError(FormulaErrorCode.syntax);

  String get token => code.token;

  @override
  String get display => code.token;

  @override
  bool operator ==(Object other) => other is FormulaError && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => code.token;
}

/// A cell's **literal** as a formula value: a YAML scalar — number,
/// string or boolean — or nothing.
FormulaValue formulaValueOfLiteral(Object? literal) => switch (literal) {
  null => FormulaBlank.instance,
  num() => FormulaNumber(literal),
  String() => FormulaText(literal),
  bool() => FormulaBoolean(literal),
  _ => FormulaText('$literal'),
};

/// A plain Dart value a **caller** hands the library — a script's argument —
/// as a formula value. A list is a range; a value that already is one passes
/// through.
FormulaValue formulaValueFromDart(Object? value) => switch (value) {
  FormulaValue() => value,
  List() => FormulaRange([for (final v in value) formulaValueFromDart(v)]),
  _ => formulaValueOfLiteral(value),
};

/// [value] as the plain Dart a script reads: a number, a string, a
/// bool or null. An error stays a [FormulaError] — it is not a plain value, and
/// flattening it to its token would make it text. A range becomes a list.
Object? formulaValueToDart(FormulaValue value) => switch (value) {
  FormulaNumber(:final value) => value,
  FormulaText(:final value) => value,
  FormulaBoolean(:final value) => value,
  FormulaBlank() || FormulaEmbedded() => null,
  FormulaRange(:final values) => [
    for (final v in values) formulaValueToDart(v),
  ],
  FormulaError() => value,
};

/// A sheet as a lowered formula reaches it: cells and ranges by
/// **0-based** index, as values. Read-only by construction — a formula never
/// writes into a sheet, and this exposes no writer.
///
/// Named `FormulaSheet` rather than `SheetView` because that name is
/// a script's view, a different surface over the same body.
abstract interface class FormulaSheet {
  FormulaValue cell(int row, int column);

  FormulaValue range(
    int topRow,
    int leftColumn,
    int bottomRow,
    int rightColumn,
  );
}

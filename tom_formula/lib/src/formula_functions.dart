/// The shared formula function library — **one library, three
/// callers**.
///
/// The catalog, the operators and the coercion rules are implemented
/// here, exactly once, as plain Dart: no interpreter, no widgets, no I/O. Three
/// callers reach the *same objects*:
///
/// 1. the grid's [FormulaEvaluator], which dispatches through
///    [formulaCatalog] rather than through a `switch` of its own;
/// 2. a user or agent **script**, through the `formula` namespace the script
///    bridge registers over this same map;
/// 3. a backend that interprets the lowered expression — its
///    lowered expressions name these functions.
///
/// One library with several callers is the reason it is a map of named
/// functions rather than a
/// `switch`: "the same object the catalog resolves for `SUM`" has to be
/// something a caller can *hold*, or "one library, three callers" is a
/// statement about intent rather than about the code. A `switch` cannot be
/// handed to anybody.
///
/// ## Arguments are thunks
///
/// Every catalog function takes `List<FormulaArg>` — a list of
/// **thunks** — and most call every one of them immediately. `IF` does not,
/// which is the whole reason for the shape: the unused branch must not be
/// evaluated, and a uniform eager signature cannot express that
/// without `IF` growing a second, lazy implementation somewhere else.
///
/// A range argument's thunk yields a [FormulaRange] of the range's values.
/// That is the *argument* path only: an operand keeps the rule that a bare
/// range in scalar position is `#VALUE!`, because operands are evaluated rather
/// than marshalled.
///
/// Every function takes and returns [FormulaValue], so error
/// propagation and coercion are properties of the library rather than
/// of each call site.
library;

import 'dart:math' as math;

import 'package:meta/meta.dart';

import 'formula_engine.dart';
import 'formula_value.dart';
import 'references.dart';

/// One argument, unevaluated.
typedef FormulaArg = FormulaValue Function();

/// One catalog function.
typedef FormulaFunction = FormulaValue Function(List<FormulaArg> args);

/// The catalog — all 24, keyed by the name a formula writes.
///
/// `const` so that the entries are canonical: `formulaCatalog['SUM']` is
/// the same object on every lookup, which is what lets a test assert that the
/// grid and a script reach one function rather than two that agree.
const Map<String, FormulaFunction> formulaCatalog = {
  // Aggregate
  'SUM': formulaSum,
  'AVERAGE': formulaAverage,
  'MIN': formulaMin,
  'MAX': formulaMax,
  'COUNT': formulaCount,
  'COUNTA': formulaCountA,
  // Math
  'ROUND': formulaRound,
  'ABS': formulaAbs,
  'INT': formulaIntFloor,
  'MOD': formulaMod,
  'SQRT': formulaSqrt,
  'POWER': formulaPowerFn,
  // Logic
  'IF': formulaIf,
  'AND': formulaAnd,
  'OR': formulaOr,
  'NOT': formulaNot,
  // Text
  'CONCAT': formulaConcat,
  'LEN': formulaLen,
  'UPPER': formulaUpper,
  'LOWER': formulaLower,
  'TRIM': formulaTrim,
  'LEFT': formulaLeft,
  'RIGHT': formulaRight,
  'MID': formulaMid,
};

/// The binary operators, keyed by the source token.
///
/// Here rather than in the evaluator for the reason the catalog is: the
/// lowered form of `a + b` is `formula.add(a, b)`, and a second implementation
/// of `+` is the divergence the differential suite exists to prevent.
const Map<String, FormulaValue Function(FormulaValue, FormulaValue)>
formulaOperators = {
  '+': formulaAdd,
  '-': formulaSubtract,
  '*': formulaMultiply,
  '/': formulaDivide,
  '^': formulaPower,
  '&': formulaConcatenate,
  '=': formulaEq,
  '<>': formulaNe,
  '<': formulaLt,
  '<=': formulaLe,
  '>': formulaGt,
  '>=': formulaGe,
};

/// The unary operators.
const Map<String, FormulaValue Function(FormulaValue)> formulaUnaryOperators = {
  '-': formulaNegate,
  '+': formulaUnaryPlus,
};

// ---------------------------------------------------------------------------
// Coercion, in one place
// ---------------------------------------------------------------------------

/// A value in numeric context, or null when it is not a number at all.
///
/// An **empty cell is 0** and a bool is 1/0. Text that parses as a
/// number is that number; text that does not is `null`, which every caller
/// reads as "not numeric" rather than as zero — the distinction aggregates need
/// to skip a text cell instead of averaging it in as nothing.
num? formulaToNum(FormulaValue value) => switch (value) {
  FormulaNumber(:final value) => value,
  FormulaBlank() => 0,
  FormulaBoolean(:final value) => value ? 1 : 0,
  FormulaText(:final value) => num.tryParse(value),
  FormulaEmbedded() || FormulaRange() || FormulaError() => null,
};

/// A value in text context.
String formulaToText(FormulaValue value) => switch (value) {
  FormulaNumber() ||
  FormulaText() ||
  FormulaBoolean() ||
  FormulaBlank() ||
  FormulaEmbedded() ||
  FormulaRange() ||
  FormulaError() => value.display,
};

/// Excel truthiness: a non-zero number, `true`, or a non-empty string.
///
/// One implementation, because `IF` needs it eagerly (over an evaluated value)
/// and the evaluator needs it lazily (to pick which branch to evaluate at all).
/// Two spellings of "is this true" is how two branches of one function come to
/// disagree.
bool formulaTruthy(FormulaValue value) => switch (value) {
  FormulaBoolean(:final value) => value,
  FormulaNumber(:final value) => value != 0,
  FormulaText(:final value) => value.isNotEmpty,
  FormulaBlank() ||
  FormulaEmbedded() ||
  FormulaRange() ||
  FormulaError() => false,
};

/// Flattens values, expanding ranges, to a flat value list.
///
/// Returns the first [FormulaError] it meets instead of the list: an error
/// propagates through every consuming formula, so an aggregate over a
/// range holding one must be that error rather than the aggregate of the rest.
Object formulaFlattenValues(List<FormulaValue> values) {
  final out = <FormulaValue>[];
  void walk(FormulaValue value) {
    if (value is FormulaRange) {
      value.values.forEach(walk);
    } else {
      out.add(value);
    }
  }

  values.forEach(walk);
  for (final value in out) {
    if (value is FormulaError) return value;
  }
  return out;
}

/// The numbers of an aggregate's arguments, or the [FormulaError] that
/// propagates.
///
/// **A range and a scalar are treated differently on purpose**, and it is the
/// rule rather than an inconsistency: a non-numeric cell *inside a
/// range* is skipped (Excel aggregates ignore text), while a non-numeric
/// *scalar* argument is a `#VALUE!` — the author named that cell, so silently
/// dropping it would answer a question they did not ask.
Object formulaAggregateNumbers(List<FormulaArg> args) {
  final numbers = <num>[];
  for (final arg in args) {
    final value = arg();
    switch (value) {
      case FormulaError():
        return value;
      case FormulaRange():
        final flat = formulaFlattenValues([value]);
        if (flat is FormulaError) return flat;
        for (final entry in flat as List<FormulaValue>) {
          if (entry is FormulaNumber) numbers.add(entry.value);
        }
      case FormulaNumber() ||
          FormulaText() ||
          FormulaBoolean() ||
          FormulaBlank() ||
          FormulaEmbedded():
        final n = formulaToNum(value);
        if (n == null) return FormulaError.value;
        numbers.add(n);
    }
  }
  return numbers;
}

/// One evaluated argument.
FormulaValue _one(List<FormulaArg> args, int index) => args[index]();

/// A number, a whole double as an int — which is what a cell displays.
FormulaNumber _number(num n) => FormulaNumber(
  n is double && n == n.roundToDouble() && n.isFinite ? n.toInt() : n,
);

// ---------------------------------------------------------------------------
// Aggregate
// ---------------------------------------------------------------------------

FormulaValue formulaSum(List<FormulaArg> args) {
  final numbers = formulaAggregateNumbers(args);
  if (numbers is FormulaError) return numbers;
  return FormulaNumber((numbers as List<num>).fold<num>(0, (a, b) => a + b));
}

FormulaValue formulaAverage(List<FormulaArg> args) {
  final numbers = formulaAggregateNumbers(args);
  if (numbers is FormulaError) return numbers;
  final list = numbers as List<num>;
  // an average over zero numbers is #DIV/0!, not 0 — there is no
  // answer, and 0 would be one.
  if (list.isEmpty) return FormulaError.div0;
  return _number(list.fold<num>(0, (a, b) => a + b) / list.length);
}

FormulaValue formulaMin(List<FormulaArg> args) {
  final numbers = formulaAggregateNumbers(args);
  if (numbers is FormulaError) return numbers;
  final list = numbers as List<num>;
  if (list.isEmpty) return FormulaError.div0;
  return FormulaNumber(list.reduce((a, b) => a < b ? a : b));
}

FormulaValue formulaMax(List<FormulaArg> args) {
  final numbers = formulaAggregateNumbers(args);
  if (numbers is FormulaError) return numbers;
  final list = numbers as List<num>;
  if (list.isEmpty) return FormulaError.div0;
  return FormulaNumber(list.reduce((a, b) => a > b ? a : b));
}

FormulaValue formulaCount(List<FormulaArg> args) {
  final numbers = formulaAggregateNumbers(args);
  if (numbers is FormulaError) return numbers;
  return FormulaNumber((numbers as List<num>).length);
}

/// COUNTA — every **non-empty, non-embedded** value.
///
/// The embedded exclusion is deliberate: an embedded cell is
/// not a value, so it is neither counted nor an error.
FormulaValue formulaCountA(List<FormulaArg> args) {
  var count = 0;
  for (final arg in args) {
    final value = arg();
    if (value is FormulaError) return value;
    final flat = formulaFlattenValues([value]);
    if (flat is FormulaError) return flat;
    for (final entry in flat as List<FormulaValue>) {
      final counted = switch (entry) {
        FormulaBlank() || FormulaEmbedded() => false,
        FormulaText(:final value) => value.isNotEmpty,
        FormulaNumber() || FormulaBoolean() || FormulaError() => true,
        // Flattened, so no range remains.
        FormulaRange() => false,
      };
      if (counted) count++;
    }
  }
  return FormulaNumber(count);
}

// ---------------------------------------------------------------------------
// Math
// ---------------------------------------------------------------------------

FormulaValue formulaRound(List<FormulaArg> args) {
  if (args.isEmpty || args.length > 2) return FormulaError.value;
  final value = _one(args, 0);
  if (value is FormulaError) return value;
  final n = formulaToNum(value);
  if (n == null) return FormulaError.value;
  var digits = 0;
  if (args.length == 2) {
    final d = _one(args, 1);
    if (d is FormulaError) return d;
    final dn = formulaToNum(d);
    if (dn == null) return FormulaError.value;
    digits = dn.toInt();
  }
  final factor = math.pow(10, digits);
  return _number((n * factor).roundToDouble() / factor);
}

FormulaValue formulaAbs(List<FormulaArg> args) {
  if (args.length != 1) return FormulaError.value;
  final value = _one(args, 0);
  if (value is FormulaError) return value;
  final n = formulaToNum(value);
  if (n == null) return FormulaError.value;
  return FormulaNumber(n.abs());
}

/// INT — **floor**, toward negative infinity, not truncation.
///
/// `INT(-1.5)` is `-2`. Truncation would give `-1`, which is what a naive
/// `toInt()` does and what Excel does not.
FormulaValue formulaIntFloor(List<FormulaArg> args) {
  if (args.length != 1) return FormulaError.value;
  final value = _one(args, 0);
  if (value is FormulaError) return value;
  final n = formulaToNum(value);
  if (n == null) return FormulaError.value;
  return FormulaNumber(n.floor());
}

/// MOD — the result takes the **sign of the divisor** (as in Excel).
///
/// `MOD(-1, 3)` is `2`, where Dart's `%` already agrees and `remainder()` would
/// give `-1`.
FormulaValue formulaMod(List<FormulaArg> args) {
  if (args.length != 2) return FormulaError.value;
  final a = _one(args, 0);
  if (a is FormulaError) return a;
  final b = _one(args, 1);
  if (b is FormulaError) return b;
  final an = formulaToNum(a);
  final bn = formulaToNum(b);
  if (an == null || bn == null) return FormulaError.value;
  if (bn == 0) return FormulaError.div0;
  final result = an - bn * (an / bn).floor();
  return _number(result);
}

FormulaValue formulaSqrt(List<FormulaArg> args) {
  if (args.length != 1) return FormulaError.value;
  final value = _one(args, 0);
  if (value is FormulaError) return value;
  final n = formulaToNum(value);
  if (n == null) return FormulaError.value;
  // Negative -> #VALUE!, not NaN: a NaN would flow into every
  // consuming formula as a number and compare unequal to itself.
  if (n < 0) return FormulaError.value;
  return _number(math.sqrt(n));
}

FormulaValue formulaPowerFn(List<FormulaArg> args) {
  if (args.length != 2) return FormulaError.value;
  final a = _one(args, 0);
  if (a is FormulaError) return a;
  final b = _one(args, 1);
  if (b is FormulaError) return b;
  return formulaPower(a, b);
}

// ---------------------------------------------------------------------------
// Logic
// ---------------------------------------------------------------------------

/// IF — the one function that does **not** evaluate all its arguments.
///
/// This is why every catalog function takes thunks. An else-less `IF` whose
/// condition is false yields `false`, which is Excel's behaviour and the one the
/// grid already had.
FormulaValue formulaIf(List<FormulaArg> args) {
  if (args.length < 2 || args.length > 3) return FormulaError.value;
  final condition = args[0]();
  if (condition is FormulaError) return condition;
  if (formulaTruthy(condition)) return args[1]();
  return args.length == 3 ? args[2]() : FormulaBoolean.no;
}

/// AND / OR are **eager**, matching Excel — unlike `IF`, every
/// argument is evaluated even once the answer is known.
FormulaValue formulaAnd(List<FormulaArg> args) => _booleanFold(args, and: true);

FormulaValue formulaOr(List<FormulaArg> args) => _booleanFold(args, and: false);

FormulaValue _booleanFold(List<FormulaArg> args, {required bool and}) {
  final flat = formulaFlattenValues([for (final arg in args) arg()]);
  if (flat is FormulaError) return flat;
  final values = flat as List<FormulaValue>;
  // Excel: AND()/OR() with nothing to decide over is an error rather than a
  // vacuous truth.
  if (values.isEmpty) return FormulaError.value;
  var any = false;
  var all = true;
  var sawOne = false;
  for (final value in values) {
    if (value is FormulaBlank) continue; // an empty cell in a range is ignored
    sawOne = true;
    if (formulaTruthy(value)) {
      any = true;
    } else {
      all = false;
    }
  }
  if (!sawOne) return FormulaError.value;
  return FormulaBoolean(and ? all : any);
}

FormulaValue formulaNot(List<FormulaArg> args) {
  if (args.length != 1) return FormulaError.value;
  final value = _one(args, 0);
  if (value is FormulaError) return value;
  return FormulaBoolean(!formulaTruthy(value));
}

// ---------------------------------------------------------------------------
// Text
// ---------------------------------------------------------------------------

FormulaValue formulaConcat(List<FormulaArg> args) {
  final flat = formulaFlattenValues([for (final arg in args) arg()]);
  if (flat is FormulaError) return flat;
  final buffer = StringBuffer();
  for (final value in flat as List<FormulaValue>) {
    buffer.write(formulaToText(value));
  }
  return FormulaText(buffer.toString());
}

FormulaValue formulaLen(List<FormulaArg> args) {
  if (args.length != 1) return FormulaError.value;
  final value = _one(args, 0);
  if (value is FormulaError) return value;
  return FormulaNumber(formulaToText(value).length);
}

FormulaValue formulaUpper(List<FormulaArg> args) =>
    _text1(args, (s) => s.toUpperCase());

FormulaValue formulaLower(List<FormulaArg> args) =>
    _text1(args, (s) => s.toLowerCase());

FormulaValue formulaTrim(List<FormulaArg> args) =>
    _text1(args, (s) => s.trim());

FormulaValue _text1(List<FormulaArg> args, String Function(String) f) {
  if (args.length != 1) return FormulaError.value;
  final value = _one(args, 0);
  if (value is FormulaError) return value;
  return FormulaText(f(formulaToText(value)));
}

/// LEFT / RIGHT — `n` defaults to 1; a negative `n` is `#VALUE!`,
/// and an `n` past the end yields the whole string rather than an error.
FormulaValue formulaLeft(List<FormulaArg> args) =>
    _sideText(args, fromLeft: true);

FormulaValue formulaRight(List<FormulaArg> args) =>
    _sideText(args, fromLeft: false);

FormulaValue _sideText(List<FormulaArg> args, {required bool fromLeft}) {
  if (args.isEmpty || args.length > 2) return FormulaError.value;
  final value = _one(args, 0);
  if (value is FormulaError) return value;
  var n = 1;
  if (args.length == 2) {
    final raw = _one(args, 1);
    if (raw is FormulaError) return raw;
    final rn = formulaToNum(raw);
    if (rn == null) return FormulaError.value;
    n = rn.toInt();
  }
  if (n < 0) return FormulaError.value;
  final text = formulaToText(value);
  if (n >= text.length) return FormulaText(text);
  return FormulaText(
    fromLeft ? text.substring(0, n) : text.substring(text.length - n),
  );
}

/// MID — `start` is **1-based** (Excel). A start below 1 is `#VALUE!`; a start
/// past the end is the empty string, not an error.
FormulaValue formulaMid(List<FormulaArg> args) {
  if (args.length != 3) return FormulaError.value;
  final value = _one(args, 0);
  if (value is FormulaError) return value;
  final rawStart = _one(args, 1);
  if (rawStart is FormulaError) return rawStart;
  final rawCount = _one(args, 2);
  if (rawCount is FormulaError) return rawCount;
  final start = formulaToNum(rawStart);
  final count = formulaToNum(rawCount);
  if (start == null || count == null) return FormulaError.value;
  if (start < 1 || count < 0) return FormulaError.value;
  final text = formulaToText(value);
  final from = start.toInt() - 1;
  if (from >= text.length) return const FormulaText('');
  final to = (from + count.toInt()).clamp(from, text.length);
  return FormulaText(text.substring(from, to));
}

// ---------------------------------------------------------------------------
// Operators
// ---------------------------------------------------------------------------

FormulaValue formulaAdd(FormulaValue a, FormulaValue b) =>
    _arith(a, b, (l, r) => l + r);
FormulaValue formulaSubtract(FormulaValue a, FormulaValue b) =>
    _arith(a, b, (l, r) => l - r);
FormulaValue formulaMultiply(FormulaValue a, FormulaValue b) =>
    _arith(a, b, (l, r) => l * r);

FormulaValue formulaDivide(FormulaValue a, FormulaValue b) {
  final error = _firstError(a, b);
  if (error != null) return error;
  final l = formulaToNum(a);
  final r = formulaToNum(b);
  if (l == null || r == null) return FormulaError.value;
  if (r == 0) return FormulaError.div0;
  return _number(l / r);
}

/// `^` and `POWER` are the same function, which is the point: a second
/// implementation of exponentiation is exactly the divergence one library forbids.
///
/// Fractional exponents work: `dart:math` is platform-neutral and web-linkable.
FormulaValue formulaPower(FormulaValue a, FormulaValue b) {
  final error = _firstError(a, b);
  if (error != null) return error;
  final l = formulaToNum(a);
  final r = formulaToNum(b);
  if (l == null || r == null) return FormulaError.value;
  final result = math.pow(l, r);
  // `pow` answers NaN for a negative base with a fractional exponent and
  // infinity on overflow. Both are numbers that would flow into every consuming
  // formula and compare unequal to themselves, so they become the error the
  // token set already has a name for.
  if (result.isNaN || result.isInfinite) return FormulaError.value;
  return _number(result);
}

FormulaValue formulaConcatenate(FormulaValue a, FormulaValue b) =>
    _firstError(a, b) ?? FormulaText(formulaToText(a) + formulaToText(b));

FormulaValue formulaEq(FormulaValue a, FormulaValue b) =>
    _firstError(a, b) ?? FormulaBoolean(_equal(a, b));
FormulaValue formulaNe(FormulaValue a, FormulaValue b) =>
    _firstError(a, b) ?? FormulaBoolean(!_equal(a, b));
FormulaValue formulaLt(FormulaValue a, FormulaValue b) =>
    _compare(a, b, (order) => order < 0);
FormulaValue formulaLe(FormulaValue a, FormulaValue b) =>
    _compare(a, b, (order) => order <= 0);
FormulaValue formulaGt(FormulaValue a, FormulaValue b) =>
    _compare(a, b, (order) => order > 0);
FormulaValue formulaGe(FormulaValue a, FormulaValue b) =>
    _compare(a, b, (order) => order >= 0);

FormulaValue formulaNegate(FormulaValue x) {
  if (x is FormulaError) return x;
  final n = formulaToNum(x);
  return n == null ? FormulaError.value : FormulaNumber(-n);
}

FormulaValue formulaUnaryPlus(FormulaValue x) {
  if (x is FormulaError) return x;
  final n = formulaToNum(x);
  return n == null ? FormulaError.value : FormulaNumber(n);
}

/// The error an operator propagates, left operand first.
///
/// In the operators rather than only in the evaluator, because the operators
/// are library members a caller can hold: the lowered form calls
/// `formula.add(a, b)` with whatever it has, and an error handed in must come
/// out, not be coerced to `#VALUE!`.
FormulaError? _firstError(FormulaValue a, FormulaValue b) =>
    a is FormulaError ? a : (b is FormulaError ? b : null);

FormulaValue _arith(FormulaValue a, FormulaValue b, num Function(num, num) f) {
  final error = _firstError(a, b);
  if (error != null) return error;
  final l = formulaToNum(a);
  final r = formulaToNum(b);
  if (l == null || r == null) return FormulaError.value;
  return FormulaNumber(f(l, r));
}

/// The ordering operators: numeric when
/// both sides coerce to numbers, else case-insensitive text — the same split
/// [_equal] makes, so `<=` is `<` or `=` for every pair of operands.
FormulaValue _compare(
  FormulaValue a,
  FormulaValue b,
  bool Function(int order) test,
) {
  final error = _firstError(a, b);
  if (error != null) return error;
  if (_notScalar(a) || _notScalar(b)) return FormulaError.value;
  return FormulaBoolean(test(_order(a, b)));
}

/// A range is never a scalar and an embedded cell has no scalar value;
/// ordering either as its display text would invent an answer.
bool _notScalar(FormulaValue value) =>
    value is FormulaRange || value is FormulaEmbedded;

/// Excel equality: numeric when both coerce to numbers, else case-insensitive
/// text.
bool _equal(FormulaValue a, FormulaValue b) => _order(a, b) == 0;

/// The order of two scalars: numeric when both coerce, else their
/// texts upper-cased and compared by code unit.
int _order(FormulaValue a, FormulaValue b) {
  final l = formulaToNum(a);
  final r = formulaToNum(b);
  if (l != null && r != null) return l.compareTo(r);
  return formulaToText(
    a,
  ).toUpperCase().compareTo(formulaToText(b).toUpperCase());
}

// ---------------------------------------------------------------------------
// Literal constructors and reach into other sheets
// ---------------------------------------------------------------------------

/// The values a lowered expression writes for its literals.
FormulaValue formulaNumber(num value) => FormulaNumber(value);
FormulaValue formulaText(String value) => FormulaText(value);
FormulaValue formulaBoolean(bool value) => FormulaBoolean(value);
FormulaValue formulaBlank() => FormulaBlank.instance;
FormulaValue formulaErrorOf(FormulaErrorCode code) => FormulaError(code);

/// The sheet [reference] names, as a lowered formula reads it, resolved
/// through [references] — the way `SheetEngine` resolves a reference a cell
/// holds: the sheet it names reads its own references through its own
/// resolver.
///
/// A reference that does not resolve to a sheet is a sheet every cell of which
/// is `#REF!`, and not a throw, because a formula is not allowed to abort.
FormulaSheetReference formulaSheet(
  String reference, {
  FormulaReferenceResolver references = const FormulaNoReferences(),
}) {
  final target = references.resolve(reference);
  final cells = target?.readCells();
  return FormulaSheetReference._(
    target == null || cells == null
        ? null
        : SheetEngine(
            Map.of(cells),
            selfId: target.id,
            references: target.references,
          ),
  );
}

/// What `formula.sheet(ref)` answers: the sheet a reference named, or — when
/// it named none — a sheet every cell of which is `#REF!`.
///
/// One concrete type whichever it is, because a caller that holds it (a script,
/// through a bridge keyed on the runtime type) has to meet one type, not an
/// engine in one case and a stand-in in the other.
final class FormulaSheetReference implements FormulaSheet {
  final SheetEngine? _engine;

  const FormulaSheetReference._(this._engine);

  /// Whether the reference resolved to a spreadsheet.
  bool get resolved => _engine != null;

  @override
  FormulaValue cell(int row, int column) =>
      _engine?.cell(row, column) ?? FormulaError.ref;

  @override
  FormulaValue range(
    int topRow,
    int leftColumn,
    int bottomRow,
    int rightColumn,
  ) =>
      _engine?.range(topRow, leftColumn, bottomRow, rightColumn) ??
      FormulaError.ref;
}

// ---------------------------------------------------------------------------
// The script-facing namespace
// ---------------------------------------------------------------------------

/// Script member name → catalog name (the rename table).
///
/// Two names differ from their catalog spelling, and both for the same reason:
/// `IF` and `INT` collide with a Dart keyword and a `dart:core` type. The table
/// is **here rather than in the bridge** so there is one mapping, and so that
/// the bridge can be built *from* it — a catalog function added tomorrow
/// appears in the `formula` namespace without anybody editing a bridge.
const Map<String, String> formulaScriptNames = {
  'sum': 'SUM',
  'average': 'AVERAGE',
  'min': 'MIN',
  'max': 'MAX',
  'count': 'COUNT',
  'countA': 'COUNTA',
  'round': 'ROUND',
  'abs': 'ABS',
  'intFloor': 'INT',
  'mod': 'MOD',
  'sqrt': 'SQRT',
  'power': 'POWER',
  'ifElse': 'IF',
  'and': 'AND',
  'or': 'OR',
  'not': 'NOT',
  'concat': 'CONCAT',
  'len': 'LEN',
  'upper': 'UPPER',
  'lower': 'LOWER',
  'trim': 'TRIM',
  'left': 'LEFT',
  'right': 'RIGHT',
  'mid': 'MID',
};

/// Single-range alias → catalog name.
///
/// `rangeSum(r)` is **defined as** `sum([r])` and is not a second
/// implementation — which is why this is a name table and not a set of
/// functions. It exists because it is the literal lowering target of
/// `=SUM(A1:C3)`: `formula.rangeSum(currentSheet.range(0, 0, 2, 2))`.
const Map<String, String> formulaRangeAliases = {
  'rangeSum': 'SUM',
  'rangeAverage': 'AVERAGE',
  'rangeMin': 'MIN',
  'rangeMax': 'MAX',
  'rangeCount': 'COUNT',
  'rangeCountA': 'COUNTA',
};

/// Operator member name → the operator's token in [formulaOperators].
/// `^` needs no entry: it and `POWER` are one function, reached as
/// `power`.
const Map<String, String> formulaOperatorNames = {
  'add': '+',
  'subtract': '-',
  'multiply': '*',
  'divide': '/',
  'concatenate': '&',
  'eq': '=',
  'ne': '<>',
  'lt': '<',
  'le': '<=',
  'gt': '>',
  'ge': '>=',
};

/// Unary operator member name → token in [formulaUnaryOperators].
const Map<String, String> formulaUnaryOperatorNames = {
  'negate': '-',
  'unaryPlus': '+',
};

/// The script members that take their arguments as **one list**:
/// the aggregates, `and`/`or` and `concat`. Every other member takes them
/// positionally. The lowerer writes `formula.sum([a, b])` from this set, and
/// the D4rt bridge reads the list back from it — one table, so the two cannot
/// disagree about which shape a member has.
const Set<String> formulaListMembers = {
  'sum',
  'average',
  'min',
  'max',
  'count',
  'countA',
  'and',
  'or',
  'concat',
};

/// Catalog functions whose arguments after the first are **branches**, lowered
/// to thunks so the unused one is not evaluated. `IF` is
/// the only one; it is a table so that the lowerer and the D4rt bridge name it
/// from here rather than each spelling the catalog name.
const Set<String> formulaBranchingFunctions = {'IF'};

/// The literal constructors by member name.
const Set<String> formulaConstructorNames = {
  'number',
  'text',
  'boolean',
  'blank',
  'error',
};

/// The `formula` namespace a script reaches — the whole surface: the 24 catalog functions under the rename table, the six
/// single-range aliases, the operators, the literal constructors and
/// [sheet].
///
/// It **holds no functions of its own**: every call resolves through
/// [formulaCatalog], [formulaOperators] or
/// [formulaUnaryOperators], so the object a script reaches for `SUM` is
/// the object the grid's evaluator reaches for `SUM` — the same entry in the
/// same map, not two that agree. That is the whole of the claim, and it
/// is assertable rather than intended because [functionFor] hands the function
/// back.
///
/// It exposes **no scheduler, no dependency graph and no way to write**.
/// A script computes with it; it changes cells through its host's own
/// views.
class FormulaNamespace {
  /// What [sheet] resolves a reference through — the references of the place
  /// the caller runs in.
  final FormulaReferenceResolver references;

  const FormulaNamespace({this.references = const FormulaNoReferences()});

  /// The catalog function [catalogName] names, or null.
  ///
  /// The identity door, and the reason it is public: "the same object the
  /// catalog resolves for `SUM`" must be something a caller — or a test — can
  /// hold.
  @visibleForTesting
  FormulaFunction? functionFor(String catalogName) =>
      formulaCatalog[catalogName];

  /// Every member [invoke] answers: catalog names, range aliases, operators
  /// and constructors. [sheet] is separate because it answers a sheet, not a
  /// value.
  static Iterable<String> get memberNames => [
    ...formulaScriptNames.keys,
    ...formulaRangeAliases.keys,
    ...formulaOperatorNames.keys,
    ...formulaUnaryOperatorNames.keys,
    ...formulaConstructorNames,
  ];

  /// Calls the catalog entry [catalogName] with already-evaluated [values].
  ///
  /// The values are wrapped as thunks here rather than at the call site,
  /// because a caller outside the grid has no unevaluated arguments to offer:
  /// by the time a script calls `formula.ifElse(a, b, c)` all three exist. The
  /// laziness the thunks buy is the *grid's*, where an argument is an AST node.
  FormulaValue call(String catalogName, List<FormulaValue> values) {
    final function = formulaCatalog[catalogName];
    if (function == null) return FormulaError.name;
    return function([for (final value in values) () => value]);
  }

  /// Calls by **member** name, from plain values or formula values alike
  /// ([formulaValueFromDart]): a list is a range.
  ///
  /// Returns `#NAME?` for an unknown member, which is the same answer the grid
  /// gives for an unknown function — one vocabulary, one failure. Arity is
  /// the function's to judge: too many arguments is `#VALUE!`, the function
  /// answering rather than the namespace failing to find it.
  FormulaValue invoke(String member, List<Object?> arguments) {
    final values = [for (final a in arguments) formulaValueFromDart(a)];
    FormulaValue at(int i) =>
        i < values.length ? values[i] : FormulaBlank.instance;

    final alias = formulaRangeAliases[member];
    if (alias != null) {
      // `rangeSum(r)` is `sum([r])`: one argument, which is the range.
      return call(alias, [
        values.isEmpty ? const FormulaRange([]) : values.first,
      ]);
    }
    final catalogName = formulaScriptNames[member];
    if (catalogName != null) return call(catalogName, values);

    final binary = formulaOperatorNames[member];
    if (binary != null) {
      if (values.length != 2) return FormulaError.value;
      return formulaOperators[binary]!(values[0], values[1]);
    }
    final unary = formulaUnaryOperatorNames[member];
    if (unary != null) {
      if (values.length != 1) return FormulaError.value;
      return formulaUnaryOperators[unary]!(values[0]);
    }
    return switch (member) {
      'number' => at(0) is FormulaNumber ? at(0) : FormulaError.value,
      // the constructors do not coerce — handed the wrong kind, each
      // answers `#VALUE!` rather than guessing what was meant.
      'text' => at(0) is FormulaText ? at(0) : FormulaError.value,
      'boolean' => at(0) is FormulaBoolean ? at(0) : FormulaError.value,
      'blank' => formulaBlank(),
      'error' => _error(arguments.isEmpty ? null : arguments.first),
      _ => FormulaError.name,
    };
  }

  /// `error(code)` takes a token (`#REF!`) or a [FormulaErrorCode] name
  /// (`ref`); anything else is not an error code, which is `#VALUE!`.
  static FormulaValue _error(Object? code) {
    if (code is FormulaErrorCode) return formulaErrorOf(code);
    if (code is String) {
      final byToken = FormulaErrorCode.fromToken(code);
      if (byToken != null) return formulaErrorOf(byToken);
      for (final c in FormulaErrorCode.values) {
        if (c.name == code) return formulaErrorOf(c);
      }
    }
    return FormulaError.value;
  }

  /// The sheet [reference] names, resolved through [references]; every cell
  /// `#REF!` when it does not resolve.
  FormulaSheetReference sheet(String reference) =>
      formulaSheet(reference, references: references);
}

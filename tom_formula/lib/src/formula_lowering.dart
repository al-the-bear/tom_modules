/// Lowering a formula AST to a Dart expression.
///
/// The lowered form is the formula's **canonical Dart rendering**: a string
/// over exactly two free identifiers, `formula` (the shared function library)
/// and `currentSheet` (the sheet the formula lives in). It is what the
/// D4rt backend evaluates and what *Show as Dart* displays; the native backend
/// never needs it.
///
/// Three properties are normative and are why this file is shaped as it is:
///
/// * **Total and closed.** Every AST the grammar produces has exactly
///   one rendering, assembled from a fixed vocabulary — the name tables of
///   `formula_functions.dart`, integer indices, and escaped literals. No piece
///   of document content can become an identifier or a receiver, which is
///   what makes a formula confined *by construction* whichever backend
///   evaluates it.
/// * **A pure function of the source string**, so it is memoised on that
///   string with no invalidation protocol: editing a formula changes the key.
/// * **Never persisted**. [FormulaLowering] is an in-memory LRU
///   and nothing else in the product stores what it returns.
library;

import 'dart:collection';

import 'package:meta/meta.dart';

import 'formula_engine.dart';
import 'formula_functions.dart';
import 'formula_value.dart';

/// The lowered Dart expression for [node].
///
/// Operators lower to calls, never to Dart operators: the AST already
/// encodes precedence and associativity, and Dart's `+` carries Dart's
/// semantics rather than the formula's.
String lowerFormula(FormulaNode node) => switch (node) {
  NumberLiteral(:final value) => 'formula.number(${_numberLiteral(value)})',
  StringLiteral(:final value) =>
    'formula.text(${formulaDartStringLiteral(value)})',
  BoolLiteral(:final value) => 'formula.boolean($value)',
  ErrorLiteral(:final error) =>
    'formula.error(FormulaErrorCode.${error.code.name})',
  // zero-based indices, and the `$` markers are consumed here — the
  // lowered form is absoluteness-free.
  CellReference(:final address, :final sheet) =>
    '${_sheet(sheet)}.cell(${address.row - 1}, ${address.column})',
  RangeReference(:final start, :final end, :final sheet) =>
    '${_sheet(sheet)}.range(${start.row - 1}, ${start.column}, '
        '${end.row - 1}, ${end.column})',
  UnaryOp(:final op, :final operand) =>
    'formula.${_unaryMember[op]}(${lowerFormula(operand)})',
  BinaryOp(:final op, :final left, :final right) =>
    'formula.${_binaryMember[op]}(${lowerFormula(left)}, '
        '${lowerFormula(right)})',
  FunctionCall() => _call(node),
};

/// `currentSheet`, or the sheet a reference names — its locator
/// emitted **verbatim** as a Dart string literal: no re-encoding,
/// relativization or normalization, because those operate on the source.
String _sheet(String? reference) => reference == null
    ? 'currentSheet'
    : 'formula.sheet(${formulaDartStringLiteral(reference)})';

String _call(FunctionCall node) {
  final name = node.name;
  // names resolve against the closed catalog only. An unknown name is
  // `#NAME?` — the same answer the native backend gives, without evaluating
  // its arguments, and without letting the name itself reach the output.
  if (!formulaCatalog.containsKey(name)) {
    return 'formula.error(FormulaErrorCode.${FormulaErrorCode.name.name})';
  }
  final member = _memberOf[name]!;
  final args = node.arguments.map(lowerFormula).toList();

  // an aggregate over exactly one range reads as its alias.
  final alias = _rangeAliasOf[name];
  if (alias != null &&
      node.arguments.length == 1 &&
      node.arguments.single is RangeReference) {
    return 'formula.$alias(${args.single})';
  }
  if (_listMembers.contains(member)) {
    return 'formula.$member([${args.join(', ')}])';
  }
  // IF's branches are thunks, so the unused one is not
  // evaluated. Every argument after the condition is thunked, including the
  // ones an arity error would reject — the catalog judges arity, not the
  // lowerer, so both backends give the same answer.
  if (formulaBranchingFunctions.contains(name) && args.isNotEmpty) {
    return 'formula.$member(${[args.first, for (final branch in args.skip(1)) '() => $branch'].join(', ')})';
  }
  return 'formula.$member(${args.join(', ')})';
}

/// Catalog name → script member, inverted from the one rename table.
final Map<String, String> _memberOf = {
  for (final entry in formulaScriptNames.entries) entry.value: entry.key,
};

/// Catalog name → single-range alias, inverted from the one alias table.
final Map<String, String> _rangeAliasOf = {
  for (final entry in formulaRangeAliases.entries) entry.value: entry.key,
};

/// The members that take their arguments as one list: the
/// aggregates, `AND`/`OR`, and `CONCAT`.
const Set<String> _listMembers = formulaListMembers;

final Map<String, String> _binaryMember = {
  for (final entry in formulaOperatorNames.entries) entry.value: entry.key,
  // `^` and POWER are one function.
  '^': 'power',
};

final Map<String, String> _unaryMember = {
  for (final entry in formulaUnaryOperatorNames.entries) entry.value: entry.key,
};

/// A number literal as Dart source. Never negative — the grammar has no
/// signed literal, a minus is a unary operator — and never infinite, so
/// `toString` is always a valid Dart literal (`1e+21` included).
String _numberLiteral(num value) => value.toString();

/// [text] as a single-quoted Dart string literal.
///
/// Escapes everything that would otherwise end the literal, start an
/// interpolation, or be unreadable in the *Show as Dart* panel. This and
/// [_numberLiteral] are the only routes from document content into a lowered
/// expression.
String formulaDartStringLiteral(String text) {
  final out = StringBuffer("'");
  for (final rune in text.runes) {
    switch (rune) {
      case 0x5C: // backslash
        out.write(r'\\');
      case 0x27: // '
        out.write(r"\'");
      case 0x24: // $
        out.write(r'\$');
      case 0x0A:
        out.write(r'\n');
      case 0x0D:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      default:
        if (rune < 0x20 || rune == 0x7F) {
          out.write('\\u{${rune.toRadixString(16)}}');
        } else {
          out.writeCharCode(rune);
        }
    }
  }
  out.write("'");
  return out.toString();
}

/// The memo: lowered strings keyed by the formula **source**, in memory
/// only, bounded LRU.
///
/// Eviction is always safe because lowering is pure and cheap. `$A$1` and
/// `A1` are separate entries though they lower identically — correct, and it
/// costs nothing.
class FormulaLowering {
  /// The recommended default.
  @visibleForTesting
  static const defaultCapacity = 4096;

  FormulaLowering({int capacity = defaultCapacity})
    : _capacity = capacity < 1 ? 1 : capacity;

  int _capacity;

  // A LinkedHashMap is insertion-ordered; re-inserting on a hit moves the
  // entry to the young end, so the first key is always the least recently
  // used.
  final LinkedHashMap<String, String?> _entries = LinkedHashMap();

  /// How many sources are held.
  int get length => _entries.length;

  int get capacity => _capacity;

  /// Changes the bound, evicting the oldest entries if it shrank.
  set capacity(int value) {
    _capacity = value < 1 ? 1 : value;
    _trim();
  }

  /// The lowered expression for [source] (with or without its `=`), or null
  /// when the grammar rejects it — such a formula is `#ERROR!` and is never
  /// lowered.
  String? lower(String source) {
    if (_entries.containsKey(source)) {
      final hit = _entries.remove(source);
      _entries[source] = hit;
      return hit;
    }
    String? lowered;
    try {
      lowered = lowerFormula(FormulaParser.parse(source));
    } on FormatException {
      lowered = null;
    }
    _entries[source] = lowered;
    _trim();
    return lowered;
  }

  /// Whether [source] is currently held — for tests of the bound.
  bool holds(String source) => _entries.containsKey(source);

  void clear() => _entries.clear();

  void _trim() {
    while (_entries.length > _capacity) {
      _entries.remove(_entries.keys.first);
    }
  }
}

/// The process's one memo. Owned by this package; a composition root may
/// resize it.
final FormulaLowering formulaLowering = FormulaLowering();

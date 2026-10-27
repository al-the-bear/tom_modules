import 'package:meta/meta.dart';

import 'cells.dart';
import 'formula_backend.dart';
import 'formula_functions.dart';
import 'formula_value.dart';
import 'references.dart';

// ---------------------------------------------------------------------------
// AST
// ---------------------------------------------------------------------------

sealed class FormulaNode {
  const FormulaNode();
}

class NumberLiteral extends FormulaNode {
  final num value;
  const NumberLiteral(this.value);
}

class StringLiteral extends FormulaNode {
  final String value;
  const StringLiteral(this.value);
}

class BoolLiteral extends FormulaNode {
  final bool value;
  const BoolLiteral(this.value);
}

/// One cell — with its `$` markers — optionally in another sheet.
///
/// The `$` flags are carried and never evaluated: they matter to
/// structural rewriting and copy/fill only. They are on the node because a
/// rewrite that re-emitted `$A$1` as `A1` would silently change what the next
/// fill does.
class CellReference extends FormulaNode {
  final CellAddress address;
  final bool absoluteColumn;
  final bool absoluteRow;

  /// The quoted reference string of the sheet this cell lives in, or null
  /// for the formula's own sheet.
  final String? sheet;

  const CellReference(
    this.address, {
    this.absoluteColumn = false,
    this.absoluteRow = false,
    this.sheet,
  });
}

class RangeReference extends FormulaNode {
  final CellAddress start;
  final CellAddress end;
  final bool startAbsoluteColumn;
  final bool startAbsoluteRow;
  final bool endAbsoluteColumn;
  final bool endAbsoluteRow;

  /// See [CellReference.sheet].
  final String? sheet;

  const RangeReference(
    this.start,
    this.end, {
    this.startAbsoluteColumn = false,
    this.startAbsoluteRow = false,
    this.endAbsoluteColumn = false,
    this.endAbsoluteRow = false,
    this.sheet,
  });

  /// All addresses in the rectangle, row-major.
  List<CellAddress> expand() => [
    for (var row = start.row; row <= end.row; row++)
      for (var col = start.column; col <= end.column; col++)
        CellAddress(col, row),
  ];
}

/// An error written into a formula as a literal — in practice `#REF!`, which
/// the row/column delete puts where a reference to a deleted cell was.
/// It evaluates to itself, so it propagates like any error.
class ErrorLiteral extends FormulaNode {
  final FormulaError error;
  const ErrorLiteral(this.error);
}

class UnaryOp extends FormulaNode {
  final String op;
  final FormulaNode operand;
  const UnaryOp(this.op, this.operand);
}

class BinaryOp extends FormulaNode {
  final String op;
  final FormulaNode left;
  final FormulaNode right;
  const BinaryOp(this.op, this.left, this.right);
}

class FunctionCall extends FormulaNode {
  final String name;
  final List<FormulaNode> arguments;
  const FunctionCall(this.name, this.arguments);
}

// ---------------------------------------------------------------------------
// Tokenizer + parser (recursive descent, Excel precedence)
// ---------------------------------------------------------------------------

class _Token {
  final String type; // number|string|ident|cell|op|eof
  final String text;
  const _Token(this.type, this.text);
}

class FormulaParser {
  /// Parses a formula (with or without the leading `=`) into an AST.
  ///
  /// Throws [FormatException] on syntax errors.
  static FormulaNode parse(String formula) {
    var source = formula.trim();
    if (source.startsWith('=')) source = source.substring(1);
    final parser = FormulaParser._(_tokenize(source));
    final node = parser._comparison();
    parser._expect('eof');
    return node;
  }

  FormulaParser._(this._tokens);

  final List<_Token> _tokens;
  int _index = 0;

  _Token get _current => _tokens[_index];

  _Token _advance() => _tokens[_index++];

  void _expect(String type) {
    if (_current.type != type) {
      throw FormatException(
        'Expected $type but found "${_current.text}" in formula',
      );
    }
    _index++;
  }

  // comparison: concat (( = | <> | < | <= | > | >= ) concat)*
  FormulaNode _comparison() {
    var node = _concat();
    while (_current.type == 'op' &&
        const {'=', '<>', '<', '<=', '>', '>='}.contains(_current.text)) {
      final op = _advance().text;
      node = BinaryOp(op, node, _concat());
    }
    return node;
  }

  FormulaNode _concat() {
    var node = _additive();
    while (_current.type == 'op' && _current.text == '&') {
      _advance();
      node = BinaryOp('&', node, _additive());
    }
    return node;
  }

  FormulaNode _additive() {
    var node = _multiplicative();
    while (_current.type == 'op' &&
        (_current.text == '+' || _current.text == '-')) {
      final op = _advance().text;
      node = BinaryOp(op, node, _multiplicative());
    }
    return node;
  }

  FormulaNode _multiplicative() {
    var node = _power();
    while (_current.type == 'op' &&
        (_current.text == '*' || _current.text == '/')) {
      final op = _advance().text;
      node = BinaryOp(op, node, _power());
    }
    return node;
  }

  // Right-associative exponentiation.
  FormulaNode _power() {
    final node = _unary();
    if (_current.type == 'op' && _current.text == '^') {
      _advance();
      return BinaryOp('^', node, _power());
    }
    return node;
  }

  FormulaNode _unary() {
    if (_current.type == 'op' &&
        (_current.text == '-' || _current.text == '+')) {
      final op = _advance().text;
      return UnaryOp(op, _unary());
    }
    return _primary();
  }

  FormulaNode _primary() {
    final token = _current;
    switch (token.type) {
      case 'number':
        _advance();
        return NumberLiteral(num.parse(token.text));
      case 'string':
        _advance();
        return StringLiteral(token.text);
      case 'error':
        _advance();
        return ErrorLiteral(
          FormulaError(FormulaErrorCode.fromToken(token.text)!),
        );
      case 'sheet':
        _advance();
        if (_current.type != 'cell') {
          throw const FormatException(
            'Expected a cell after the sheet reference in formula',
          );
        }
        return _reference(_advance().text, token.text);
      case 'cell':
        _advance();
        return _reference(token.text, null);
      case 'ident':
        _advance();
        final upper = token.text.toUpperCase();
        if (upper == 'TRUE') return const BoolLiteral(true);
        if (upper == 'FALSE') return const BoolLiteral(false);
        _expect('(');
        final arguments = <FormulaNode>[];
        if (_current.type != ')') {
          arguments.add(_comparison());
          while (_current.type == 'op' && _current.text == ',') {
            _advance();
            arguments.add(_comparison());
          }
        }
        _expect(')');
        return FunctionCall(upper, arguments);
      case '(':
        _advance();
        final node = _comparison();
        _expect(')');
        return node;
      default:
        throw FormatException('Unexpected "${token.text}" in formula');
    }
  }

  /// A cell or a range starting at [first], in [sheet] when that is set.
  FormulaNode _reference(String first, String? sheet) {
    final start = _Cell.parse(first);
    if (_current.type == 'op' && _current.text == ':') {
      _advance();
      if (_current.type != 'cell') {
        throw const FormatException('Expected cell after ":" in range');
      }
      final end = _Cell.parse(_advance().text);
      return RangeReference(
        start.address,
        end.address,
        startAbsoluteColumn: start.absoluteColumn,
        startAbsoluteRow: start.absoluteRow,
        endAbsoluteColumn: end.absoluteColumn,
        endAbsoluteRow: end.absoluteRow,
        sheet: sheet,
      );
    }
    return CellReference(
      start.address,
      absoluteColumn: start.absoluteColumn,
      absoluteRow: start.absoluteRow,
      sheet: sheet,
    );
  }

  static final RegExp _cellToken = RegExp(
    r'^\$?[A-Z]+\$?[1-9][0-9]*(?![A-Za-z0-9_$])',
  );

  static List<_Token> _tokenize(String source) {
    final tokens = <_Token>[];
    var i = 0;
    while (i < source.length) {
      final char = source[i];
      if (char == ' ' || char == '\t') {
        i++;
        continue;
      }
      // Numbers: 12, 3.5
      final numberMatch = RegExp(
        r'^[0-9]+(\.[0-9]+)?',
      ).firstMatch(source.substring(i));
      if (numberMatch != null) {
        tokens.add(_Token('number', numberMatch.group(0)!));
        i += numberMatch.end;
        continue;
      }
      // Strings: "text" with "" escaping the quote (Excel style).
      if (char == '"') {
        final buffer = StringBuffer();
        i++;
        while (i < source.length) {
          if (source[i] == '"') {
            if (i + 1 < source.length && source[i + 1] == '"') {
              buffer.write('"');
              i += 2;
              continue;
            }
            break;
          }
          buffer.write(source[i]);
          i++;
        }
        if (i >= source.length) {
          throw const FormatException('Unterminated string in formula');
        }
        i++; // closing quote
        tokens.add(_Token('string', buffer.toString()));
        continue;
      }
      // error literals (`#REF!` and its siblings), matched exactly: a
      // `#` that begins none of them is not a token.
      if (char == '#') {
        final code = FormulaErrorCode.values
            .where((c) => source.startsWith(c.token, i))
            .firstOrNull;
        if (code == null) {
          throw FormatException('Unexpected character "#" in formula');
        }
        tokens.add(_Token('error', code.token));
        i += code.token.length;
        continue;
      }
      // a quoted reference string, then `!`, names another sheet.
      if (char == "'") {
        final close = source.indexOf("'", i + 1);
        if (close < 0) {
          throw const FormatException(
            'Unterminated sheet reference in formula',
          );
        }
        if (close + 1 >= source.length || source[close + 1] != '!') {
          throw const FormatException(
            'Expected "!" after the sheet reference in formula',
          );
        }
        tokens.add(_Token('sheet', source.substring(i + 1, close)));
        i = close + 2;
        continue;
      }
      // Cell references (`$` included), then identifiers.
      final cellMatch = _cellToken.firstMatch(source.substring(i));
      if (cellMatch != null) {
        tokens.add(_Token('cell', cellMatch.group(0)!));
        i += cellMatch.end;
        continue;
      }
      final wordMatch = RegExp(
        r'^[A-Za-z_][A-Za-z0-9_]*',
      ).firstMatch(source.substring(i));
      if (wordMatch != null) {
        tokens.add(_Token('ident', wordMatch.group(0)!));
        i += wordMatch.end;
        continue;
      }
      // Two-char operators first.
      if (i + 1 < source.length) {
        final pair = source.substring(i, i + 2);
        if (pair == '<>' || pair == '<=' || pair == '>=') {
          tokens.add(_Token('op', pair));
          i += 2;
          continue;
        }
      }
      if ('+-*/^&=<>:,'.contains(char)) {
        tokens.add(_Token('op', char));
        i++;
        continue;
      }
      if (char == '(' || char == ')') {
        tokens.add(_Token(char, char));
        i++;
        continue;
      }
      throw FormatException('Unexpected character "$char" in formula');
    }
    tokens.add(const _Token('eof', ''));
    return tokens;
  }

  /// All cell addresses **of its own sheet** a formula depends on (ranges
  /// expanded). A reference into another sheet is not one of them.
  static Set<CellAddress> dependencies(FormulaNode node) {
    final out = <CellAddress>{};
    void walk(FormulaNode n) {
      switch (n) {
        case CellReference(:final address, :final sheet):
          if (sheet == null) out.add(address);
        case RangeReference(:final sheet):
          if (sheet == null) out.addAll(n.expand());
        case UnaryOp(:final operand):
          walk(operand);
        case BinaryOp(:final left, :final right):
          walk(left);
          walk(right);
        case FunctionCall(:final arguments):
          arguments.forEach(walk);
        default:
          break;
      }
    }

    walk(node);
    return out;
  }

  /// The cells a formula reads **in other sheets**, as the quoted
  /// reference string each is written with and the address read (ranges
  /// expanded) — the other half of [dependencies], taken from the same AST.
  ///
  /// The reference is returned as written, because what it names depends on
  /// the place holding the formula; the engine turns it into a
  /// `(sheetId, address)` pair for its index.
  static Set<(String, CellAddress)> sheetDependencies(FormulaNode node) {
    final out = <(String, CellAddress)>{};
    void walk(FormulaNode n) {
      switch (n) {
        case CellReference(:final address, :final sheet):
          if (sheet != null) out.add((sheet, address));
        case RangeReference(:final sheet):
          if (sheet != null) {
            for (final address in n.expand()) {
              out.add((sheet, address));
            }
          }
        case UnaryOp(:final operand):
          walk(operand);
        case BinaryOp(:final left, :final right):
          walk(left);
          walk(right);
        case FunctionCall(:final arguments):
          arguments.forEach(walk);
        default:
          break;
      }
    }

    walk(node);
    return out;
  }
}

/// A cell token split into its address and its two `$` markers.
class _Cell {
  final CellAddress address;
  final bool absoluteColumn;
  final bool absoluteRow;

  const _Cell(this.address, this.absoluteColumn, this.absoluteRow);

  static final RegExp _pattern = RegExp(r'^(\$?)([A-Z]+)(\$?)([1-9][0-9]*)$');

  static _Cell parse(String token) {
    final match = _pattern.firstMatch(token);
    if (match == null) throw FormatException('Not a cell reference: "$token"');
    return _Cell(
      CellAddress.parse('${match.group(2)}${match.group(4)}'),
      match.group(1)!.isNotEmpty,
      match.group(3)!.isNotEmpty,
    );
  }
}

// ---------------------------------------------------------------------------
// Printer — the inverse of the parser
// ---------------------------------------------------------------------------

/// Emits a formula AST as source, with the leading `=`.
///
/// The inverse of [FormulaParser.parse] up to whitespace and redundant
/// parentheses: the AST keeps neither, so the printer re-derives the
/// parentheses an expression **needs** from operator precedence. It exists for
/// structural rewriting — a reference can only be moved by parsing the
/// formula, changing the node and printing it again; doing it on the string
/// rewrites the `A1` inside `"see A1"` too.
String formulaSource(FormulaNode node) => '=${_print(node, 0)}';

/// The reference text of one cell — `$A$1`, `B2` — without any sheet prefix.
String formulaCellReferenceText(
  CellAddress address, {
  bool absoluteColumn = false,
  bool absoluteRow = false,
}) =>
    '${absoluteColumn ? r'$' : ''}'
    '${CellAddress.lettersFromColumnIndex(address.column)}'
    '${absoluteRow ? r'$' : ''}${address.row}';

const Map<String, int> _precedence = {
  '=': 1,
  '<>': 1,
  '<': 1,
  '<=': 1,
  '>': 1,
  '>=': 1,
  '&': 2,
  '+': 3,
  '-': 3,
  '*': 4,
  '/': 4,
  '^': 5,
};

String _print(FormulaNode node, int parent) {
  switch (node) {
    case NumberLiteral(:final value):
      return FormulaNumber(value).display;
    case StringLiteral(:final value):
      return '"${value.replaceAll('"', '""')}"';
    case BoolLiteral(:final value):
      return value ? 'TRUE' : 'FALSE';
    case ErrorLiteral(:final error):
      return error.token;
    case CellReference():
      final prefix = node.sheet == null ? '' : "'${node.sheet}'!";
      return '$prefix${formulaCellReferenceText(node.address, absoluteColumn: node.absoluteColumn, absoluteRow: node.absoluteRow)}';
    case RangeReference():
      final prefix = node.sheet == null ? '' : "'${node.sheet}'!";
      final start = formulaCellReferenceText(
        node.start,
        absoluteColumn: node.startAbsoluteColumn,
        absoluteRow: node.startAbsoluteRow,
      );
      final end = formulaCellReferenceText(
        node.end,
        absoluteColumn: node.endAbsoluteColumn,
        absoluteRow: node.endAbsoluteRow,
      );
      return '$prefix$start:$end';
    case UnaryOp(:final op, :final operand):
      // Unary binds tighter than every binary operator, so its operand needs
      // parentheses whenever it is one.
      final text = '$op${_print(operand, 6)}';
      return parent > 6 ? '($text)' : text;
    case BinaryOp(:final op, :final left, :final right):
      final own = _precedence[op] ?? 0;
      // `^` is right-associative; every other operator is left-associative.
      // The side an equal-precedence child would *not* have parsed on is the
      // side that needs the parentheses.
      final rightAssociative = op == '^';
      final l = _print(left, rightAssociative ? own + 1 : own);
      final r = _print(right, rightAssociative ? own : own + 1);
      final text = '$l$op$r';
      return own < parent ? '($text)' : text;
    case FunctionCall(:final name, :final arguments):
      return '$name(${arguments.map((a) => _print(a, 0)).join(',')})';
  }
}

// ---------------------------------------------------------------------------
// Evaluator
// ---------------------------------------------------------------------------

/// The native backend's AST walk.
///
/// Scalar semantics follow Excel where it is cheap to do so: empty cells act
/// as `0` in numeric context and `""` in string context; error values
/// propagate; a range used as a scalar is `#VALUE!`. Every cell is read
/// through [context]'s sheets — the same two accessors a lowered expression
/// calls — so an embedded cell's scalar rule and a reference's `#REF!` are
/// decided once, by the sheet, for both backends.
class FormulaEvaluator {
  final FormulaEvaluationContext context;

  const FormulaEvaluator(this.context);

  FormulaSheet _sheetOf(String? reference) =>
      reference == null ? context.currentSheet : context.sheet(reference);

  FormulaValue evaluate(FormulaNode node) {
    switch (node) {
      case NumberLiteral(:final value):
        return FormulaNumber(value);
      case StringLiteral(:final value):
        return FormulaText(value);
      case BoolLiteral(:final value):
        return FormulaBoolean(value);
      case ErrorLiteral(:final error):
        return error;
      case CellReference(:final address, :final sheet):
        return _sheetOf(sheet).cell(address.row - 1, address.column);
      case RangeReference():
        return FormulaError.value;
      case UnaryOp(:final op, :final operand):
        final v = evaluate(operand);
        if (v is FormulaError) return v;
        final f = formulaUnaryOperators[op];
        return f == null ? FormulaError.generic : f(v);
      case BinaryOp():
        return _binary(node);
      case FunctionCall():
        return _call(node);
    }
  }

  FormulaValue _binary(BinaryOp node) {
    final left = evaluate(node.left);
    if (left is FormulaError) return left;
    final right = evaluate(node.right);
    if (right is FormulaError) return right;
    final f = formulaOperators[node.op];
    return f == null ? FormulaError.generic : f(left, right);
  }

  /// Dispatches a call through [formulaCatalog] — the **one** library.
  ///
  /// The arguments are handed over as **thunks**, which is what lets `IF` leave
  /// a branch unevaluated without needing an implementation of its own here.
  /// A range argument marshals to a [FormulaRange] of its values; that is the
  /// argument path only, and `evaluate` keeps the rule that a bare range in
  /// *scalar* position is `#VALUE!`.
  FormulaValue _call(FunctionCall node) {
    final function = formulaCatalog[node.name];
    if (function == null) return FormulaError.name;
    return function([
      for (final argument in node.arguments) () => _argument(argument),
    ]);
  }

  /// One argument, evaluated — a range as the list of its values.
  FormulaValue _argument(FormulaNode node) {
    if (node is RangeReference) {
      return _sheetOf(node.sheet).range(
        node.start.row - 1,
        node.start.column,
        node.end.row - 1,
        node.end.column,
      );
    }
    return evaluate(node);
  }
}

// ---------------------------------------------------------------------------
// Sheet engine — dependency tracking + recalculation on edit
// ---------------------------------------------------------------------------

/// One cell of one sheet: what a dependency on another sheet names.
///
/// Keyed by the sheet's **id**, not by the reference string a formula wrote,
/// because one sheet is written differently from every place that reads it,
/// and the index has to meet an edit in the sheet under one name.
typedef FormulaCellKey = (String sheetId, CellAddress address);

/// Computes and caches the values of a grid of [cells], tracking formula
/// dependencies so an edit recalculates exactly its transitive dependents.
///
/// The index holds both kinds of read: the cells of this sheet a formula
/// reads, and the `(sheetId, address)` pairs it reads in **other** sheets
/// through a quoted reference. The second kind is what [readersOf] and
/// [recalculateReaders] answer from, so a registry of engines can carry an
/// edit in one sheet to every sheet that reads it.
///
/// Cycles are found structurally, by one Tarjan pass over the formula graph
/// per recalculation — across sheets where a formula reads another one — so
/// every cell **on or downstream of** a cycle is `#CYCLE!`, including one
/// whose `IF` would not have taken the branch that reaches it. The pass is
/// linear in the cells it visits, which is what keeps a cold load linear.
class SheetEngine implements FormulaSheet {
  /// The cells, address to cell. The engine writes edits made through
  /// [setValue], [setFormula], [setRaw] and [synchronize] into this map, so a
  /// caller that handed in its own map sees them.
  final Map<CellAddress, FormulaCell> cells;

  final Map<CellAddress, FormulaValue> _computed = {};
  final Map<CellAddress, FormulaProgram> _asts = {};
  final Map<CellAddress, Set<CellAddress>> _dependsOn = {};
  final Map<CellAddress, Set<CellAddress>> _dependents = {};

  /// Per formula cell, the cells it reads in other sheets: the reference as
  /// written (what it is resolved through), the sheet it names, and the
  /// address.
  final Map<CellAddress, Set<(String, String, CellAddress)>> _crossReads = {};

  /// The reverse of [_crossReads]: sheet id → address there → the formula
  /// cells of this sheet that read it.
  final Map<String, Map<CellAddress, Set<CellAddress>>> _crossReaders = {};

  /// The formula cells on or downstream of a dependency cycle.
  final Set<CellAddress> _cyclic = {};

  /// Cells whose value an edit changed since [synchronize] last reported.
  final Set<CellAddress> _unsynchronized = {};

  /// Addresses recomputed by the most recent edit (dependency-tracking
  /// evidence for tests; includes the edited cell itself).
  @visibleForTesting
  List<CellAddress> lastRecalculated = const [];

  /// The id of this sheet, when it has one. A local reference to it is a read
  /// of this sheet in all but spelling, and a cycle through other sheets is
  /// recognised by coming back to it.
  final String? selfId;

  /// How the quoted references written in this sheet's formulas resolve;
  /// with the default every one is `#REF!`.
  final FormulaReferenceResolver references;

  /// The backend every formula cell of this sheet is evaluated by. The
  /// scheduler — this class — owns the graph and the order; the backend only
  /// evaluates.
  final FormulaEvaluationBackend backend;

  /// [backend] defaults to the process's one ([formulaBackend]).
  SheetEngine(
    this.cells, {
    this.selfId,
    this.references = const FormulaNoReferences(),
    FormulaEvaluationBackend? backend,
  }) : backend = backend ?? formulaBackend {
    for (final entry in cells.entries) {
      _index(entry.key, entry.value);
    }
    _recalculate(cells.keys.toSet(), report: false);
  }

  /// The computed value of [address]: the literal for a value cell, the
  /// result (or [FormulaError]) for a formula cell, [FormulaEmbedded] for an
  /// embedded cell and [FormulaBlank] for an empty one.
  FormulaValue valueOf(CellAddress address) =>
      _computed[address] ?? _lookup(address);

  /// A cell by **0-based** row and column — what a lowered formula reads. A
  /// **scalar** read: an embedded cell is `#VALUE!`.
  @override
  FormulaValue cell(int row, int column) =>
      formulaScalarCellValue(valueOf(CellAddress(column, row + 1)));

  /// A rectangle by 0-based, inclusive indices, as the range argument an
  /// aggregate takes.
  @override
  FormulaValue range(
    int topRow,
    int leftColumn,
    int bottomRow,
    int rightColumn,
  ) => FormulaRange([
    for (var r = topRow; r <= bottomRow; r++)
      for (var c = leftColumn; c <= rightColumn; c++)
        valueOf(CellAddress(c, r + 1)),
  ]);

  /// Direct + transitive formula dependents of [address] in this sheet.
  @visibleForTesting
  Set<CellAddress> dependentsOf(CellAddress address) {
    final out = <CellAddress>{};
    final pending = [address];
    while (pending.isNotEmpty) {
      for (final dependent
          in _dependents[pending.removeLast()] ?? const <CellAddress>{}) {
        if (out.add(dependent)) pending.add(dependent);
      }
    }
    return out;
  }

  /// The cells [address]'s formula reads in other sheets, as
  /// `(sheetId, address)` pairs.
  @visibleForTesting
  Set<FormulaCellKey> crossDependenciesOf(CellAddress address) => {
    for (final (_, sheetId, target)
        in _crossReads[address] ?? const <(String, String, CellAddress)>{})
      (sheetId, target),
  };

  /// The formula cells of this sheet that read [sheetId] — at [addresses], or
  /// anywhere in it when that is null.
  @visibleForTesting
  Set<CellAddress> readersOf(
    String sheetId, [
    Iterable<CellAddress>? addresses,
  ]) {
    final bySheet = _crossReaders[sheetId];
    if (bySheet == null) return const {};
    if (addresses == null) {
      return {for (final readers in bySheet.values) ...readers};
    }
    return {for (final address in addresses) ...?bySheet[address]};
  }

  /// Whether [address] is on or downstream of a dependency cycle.
  @visibleForTesting
  bool isCyclic(CellAddress address) => _cyclic.contains(address);

  /// Recalculates the cells of this sheet that read [sheetId] (at
  /// [addresses], or anywhere when null) plus their transitive dependents,
  /// because that sheet changed. Returns the cells whose **value** changed.
  Set<CellAddress> recalculateReaders(
    String sheetId, [
    Iterable<CellAddress>? addresses,
  ]) {
    final readers = readersOf(sheetId, addresses);
    if (readers.isEmpty) return const {};
    final dirty = {
      ...readers,
      for (final reader in readers) ...dependentsOf(reader),
    };
    lastRecalculated = dirty.toList()..sort();
    return _recalculate(dirty);
  }

  /// Brings [cells] in line with [fresh] — the cells as the caller now stores
  /// them — recalculating exactly what differs and what depends on it.
  ///
  /// Returns every cell whose value changed since the previous call: the ones
  /// this call recalculated and the ones edits through [setValue],
  /// [setFormula] and [setRaw] changed in between. That is the shape a writer
  /// needs: an editor changes [cells] in place and then stores them, so by the
  /// time the stored cells arrive here there is nothing left to apply, and
  /// what changed is what the edit recorded.
  Set<CellAddress> synchronize(Map<CellAddress, FormulaCell> fresh) {
    final changed = {..._unsynchronized};
    _unsynchronized.clear();
    final differing = <CellAddress>{
      for (final address in {...cells.keys, ...fresh.keys})
        if (!_sameCell(cells[address], fresh[address])) address,
    };
    if (differing.isEmpty) return changed;
    for (final address in differing) {
      final cell = fresh[address];
      _unindex(address);
      if (cell == null) {
        cells.remove(address);
      } else {
        cells[address] = cell;
        _index(address, cell);
      }
    }
    final dirty = {
      ...differing,
      for (final address in differing) ...dependentsOf(address),
    };
    lastRecalculated = dirty.toList()..sort();
    return changed..addAll(_recalculate(dirty));
  }

  /// Sets a literal value and recalculates dependents.
  void setValue(CellAddress address, Object? value) =>
      _edit(address, FormulaCell.value(value));

  /// Sets a formula (leading `=`) and recalculates it plus dependents.
  void setFormula(CellAddress address, String formula) =>
      _edit(address, FormulaCell.formula(formula));

  /// Applies a raw user edit: `=…` becomes a formula, numeric text a number,
  /// anything else a string value.
  void setRaw(CellAddress address, String raw) {
    if (raw.startsWith('=')) {
      setFormula(address, raw);
    } else {
      setValue(address, num.tryParse(raw) ?? raw);
    }
  }

  void _edit(CellAddress address, FormulaCell cell) {
    cells[address] = cell;
    _unindex(address);
    _index(address, cell);
    final dirty = {address, ...dependentsOf(address)};
    _unsynchronized.addAll(_recalculate(dirty));
    lastRecalculated = dirty.toList()..sort();
  }

  void _index(CellAddress address, FormulaCell cell) {
    if (cell.kind != FormulaCellKind.formula) return;
    final FormulaNode ast;
    try {
      ast = FormulaParser.parse(cell.formula!);
    } on FormatException {
      _computed[address] = FormulaError.generic;
      return;
    }
    _asts[address] = FormulaProgram(cell.formula!, ast);
    // Dependencies come from the AST, before — and independent of — any
    // lowering.
    final local = FormulaParser.dependencies(ast);
    final cross = <(String, String, CellAddress)>{};
    for (final (reference, target) in FormulaParser.sheetDependencies(ast)) {
      final name = references.nameOf(reference);
      // A reference that names nothing is `#REF!` and reads nothing.
      if (name == null) continue;
      if (_isSelf(name)) {
        local.add(target);
      } else {
        cross.add((reference, name.id, target));
      }
    }
    _dependsOn[address] = local;
    for (final dependency in local) {
      _dependents.putIfAbsent(dependency, () => {}).add(address);
    }
    if (cross.isEmpty) return;
    _crossReads[address] = cross;
    for (final (_, sheetId, target) in cross) {
      _crossReaders
          .putIfAbsent(sheetId, () => {})
          .putIfAbsent(target, () => {})
          .add(address);
    }
  }

  void _unindex(CellAddress address) {
    _asts.remove(address);
    for (final dependency
        in _dependsOn.remove(address) ?? const <CellAddress>{}) {
      _dependents[dependency]?.remove(address);
    }
    for (final (_, sheetId, target)
        in _crossReads.remove(address) ??
            const <(String, String, CellAddress)>{}) {
      final bySheet = _crossReaders[sheetId];
      if (bySheet == null) continue;
      final readers = bySheet[target];
      readers?.remove(address);
      if (readers != null && readers.isEmpty) bySheet.remove(target);
      if (bySheet.isEmpty) _crossReaders.remove(sheetId);
    }
  }

  /// Whether [name] names this engine's own sheet from inside it.
  bool _isSelf(FormulaSheetName name) =>
      name.local && selfId != null && name.id == selfId;

  /// Recomputes [dirty] — which must be closed under [dependentsOf] — and
  /// returns the cells whose value changed (when [report]).
  Set<CellAddress> _recalculate(Set<CellAddress> dirty, {bool report = true}) {
    final before = report
        ? {for (final address in dirty) address: valueOf(address)}
        : const <CellAddress, FormulaValue>{};
    final formulaCells = <CellAddress>[];
    for (final address in dirty) {
      _cyclic.remove(address);
      final cell = cells[address];
      switch (cell?.kind) {
        case null:
          _computed.remove(address);
        case FormulaCellKind.value:
          _computed[address] = formulaValueOfLiteral(cell!.value);
        case FormulaCellKind.embedded:
          // An embedded cell has no scalar value; formulas referencing it see
          // #VALUE! via _lookup.
          _computed.remove(address);
        case FormulaCellKind.formula:
          if (_asts.containsKey(address)) {
            formulaCells.add(address);
          } else {
            // A formula that does not parse: `#ERROR!`, with its source
            // kept. It has no program and extracted no dependencies.
            _computed[address] = FormulaError.generic;
          }
      }
    }
    if (formulaCells.isNotEmpty) {
      final pass = _RecalculationPass(this, dirty);
      for (final address in formulaCells) {
        pass.run(address);
      }
    }
    if (!report) return const {};
    return {
      for (final MapEntry(:key, :value) in before.entries)
        if (!_sameValue(value, valueOf(key))) key,
    };
  }

  FormulaValue _lookup(CellAddress address) {
    final cell = cells[address];
    if (cell == null) return FormulaBlank.instance;
    return switch (cell.kind) {
      FormulaCellKind.embedded => FormulaEmbedded.instance,
      // Not yet computed only while a pass is running, for a cell it has not
      // reached — which the evaluation order never reads.
      FormulaCellKind.formula => _computed[address] ?? FormulaBlank.instance,
      FormulaCellKind.value => formulaValueOfLiteral(cell.value),
    };
  }
}

/// Whether two values are the same for the purpose of "did this cell change"
/// — `==`, except that a number that is not equal to itself (NaN) is the same
/// as itself, or a recalculation could report it changed forever.
bool _sameValue(FormulaValue a, FormulaValue b) =>
    a == b || (a.runtimeType == b.runtimeType && a.display == b.display);

bool _sameCell(FormulaCell? a, FormulaCell? b) =>
    a == null ? b == null : a.sameAs(b);

/// One recalculation: the order, the cycles and the reads of other sheets of
/// one call to `_recalculate`.
///
/// The formula graph it walks has a node per formula cell — of this sheet,
/// and of every other sheet a formula reaches through a reference — and an
/// edge from a formula to each formula it reads. One Tarjan walk finds its
/// strongly connected components and emits them **dependencies first**, which
/// is the evaluation order; a component with more than one member, or one that
/// reads itself, is a cycle, and a component that reads a cyclic one is
/// downstream of it. Both are `#CYCLE!`, decided from the graph and never from
/// which branch an `IF` took.
///
/// Only this sheet's **dirty** formula cells are nodes to evaluate. A clean
/// cell of this sheet is a leaf: an edit reaches every cell whose inputs it
/// changed through the dependents index, so a cell outside the dirty set kept
/// both its value and its cycle status. Another sheet's formula cells are
/// nodes too — for their cycle status only; their values are computed on
/// demand, once per pass, when a formula of this sheet reads them.
final class _RecalculationPass {
  _RecalculationPass(this.engine, this.dirty);

  final SheetEngine engine;
  final Set<CellAddress> dirty;

  String get _self => engine.selfId ?? '';

  /// Every other sheet this pass has resolved, by id.
  final Map<String, FormulaSheetTarget> _targets = {};

  /// Cells of other sheets read this pass. Null for one whose cells cannot be
  /// read, which reads as unresolved (`#REF!`).
  final Map<String, Map<CellAddress, FormulaCell>?> _cells = {};

  final Map<FormulaCellKey, FormulaNode?> _remoteAsts = {};
  final Map<FormulaCellKey, FormulaValue> _remoteValues = {};

  /// Finished nodes: on or downstream of a cycle, or not.
  final Map<FormulaCellKey, bool> _cyclic = {};

  /// Evaluates the dirty formula cell [address] and everything it waits on.
  void run(CellAddress address) {
    final key = (_self, address);
    if (!_cyclic.containsKey(key)) _walk(key);
  }

  bool _isLocal(FormulaCellKey key) => key.$1 == _self;

  /// Whether [key] is a node of this pass's graph.
  bool _isNode(FormulaCellKey key) {
    if (_isLocal(key)) {
      return dirty.contains(key.$2) && engine._asts.containsKey(key.$2);
    }
    return _remoteAst(key) != null;
  }

  /// The cycle status of a cell that is not a node: a clean formula of this
  /// sheet keeps the one it had; anything else is a value, a blank, an
  /// embedded cell or a formula that does not parse, none of which is on a
  /// cycle.
  bool _leafCyclic(FormulaCellKey key) =>
      _isLocal(key) && engine._cyclic.contains(key.$2);

  bool _cyclicOf(FormulaCellKey key) {
    final known = _cyclic[key];
    if (known != null) return known;
    if (!_isNode(key)) return _leafCyclic(key);
    _walk(key);
    return _cyclic[key]!;
  }

  /// The cells [key]'s formula reads, as keys.
  List<FormulaCellKey> _successors(FormulaCellKey key) {
    final (sheetId, address) = key;
    final out = <FormulaCellKey>[];
    if (_isLocal(key)) {
      for (final dependency
          in engine._dependsOn[address] ?? const <CellAddress>{}) {
        out.add((_self, dependency));
      }
      for (final (reference, _, target)
          in engine._crossReads[address] ??
              const <(String, String, CellAddress)>{}) {
        final resolved = _resolve(reference, engine.references);
        if (resolved != null) out.add((_keyOf(resolved), target));
      }
      return out;
    }
    final ast = _remoteAst(key)!;
    for (final dependency in FormulaParser.dependencies(ast)) {
      out.add((sheetId, dependency));
    }
    final holder = _targets[sheetId]!;
    for (final (reference, target) in FormulaParser.sheetDependencies(ast)) {
      final resolved = _resolve(reference, holder.references);
      if (resolved != null) out.add((_keyOf(resolved), target));
    }
    return out;
  }

  String _keyOf(FormulaSheetTarget target) =>
      target.id == engine.selfId ? _self : target.id;

  /// The sheet [reference] names through [references], or null.
  FormulaSheetTarget? _resolve(
    String reference,
    FormulaReferenceResolver references,
  ) {
    final target = references.resolve(reference);
    if (target == null) return null;
    if (target.id != engine.selfId && _cellsOf(target) == null) return null;
    _targets[target.id] ??= target;
    return target;
  }

  Map<CellAddress, FormulaCell>? _cellsOf(FormulaSheetTarget target) =>
      _cells.putIfAbsent(target.id, target.readCells);

  /// The AST of another sheet's formula cell, or null when [key] holds no
  /// formula that parses.
  FormulaNode? _remoteAst(FormulaCellKey key) =>
      _remoteAsts.putIfAbsent(key, () {
        final cell = _cells[key.$1]?[key.$2];
        if (cell == null || cell.kind != FormulaCellKind.formula) {
          return null;
        }
        try {
          return FormulaParser.parse(cell.formula!);
        } on FormatException {
          return null;
        }
      });

  /// Tarjan's algorithm from [root], iteratively — a chain of formulas is as
  /// deep as a sheet is long, and the walk must not be bounded by the stack.
  void _walk(FormulaCellKey root) {
    final index = <FormulaCellKey, int>{};
    final low = <FormulaCellKey, int>{};
    final successors = <FormulaCellKey, List<FormulaCellKey>>{};
    final stack = <FormulaCellKey>[];
    final onStack = <FormulaCellKey>{};
    final frames = <_Frame>[];
    var counter = 0;

    void open(FormulaCellKey key) {
      index[key] = counter;
      low[key] = counter;
      counter++;
      stack.add(key);
      onStack.add(key);
      final next = _successors(key);
      successors[key] = next;
      frames.add(_Frame(key, next));
    }

    open(root);
    while (frames.isNotEmpty) {
      final frame = frames.last;
      if (frame.next < frame.successors.length) {
        final successor = frame.successors[frame.next++];
        if (_cyclic.containsKey(successor) || !_isNode(successor)) continue;
        final seen = index[successor];
        if (seen == null) {
          open(successor);
        } else if (onStack.contains(successor) && seen < low[frame.key]!) {
          low[frame.key] = seen;
        }
        continue;
      }
      frames.removeLast();
      final key = frame.key;
      if (frames.isNotEmpty) {
        final parent = frames.last.key;
        if (low[key]! < low[parent]!) low[parent] = low[key]!;
      }
      if (low[key] != index[key]) continue;
      final members = <FormulaCellKey>[];
      FormulaCellKey member;
      do {
        member = stack.removeLast();
        onStack.remove(member);
        members.add(member);
      } while (member != key);
      _finish(members, successors);
    }
  }

  /// Settles one strongly connected component, whose successors outside it
  /// are all settled already.
  void _finish(
    List<FormulaCellKey> members,
    Map<FormulaCellKey, List<FormulaCellKey>> successors,
  ) {
    final memberSet = members.toSet();
    var cyclic =
        members.length > 1 ||
        successors[members.single]!.contains(members.single);
    if (!cyclic) {
      search:
      for (final member in members) {
        for (final successor in successors[member]!) {
          if (memberSet.contains(successor)) continue;
          if (_cyclic[successor] ?? _leafCyclic(successor)) {
            cyclic = true;
            break search;
          }
        }
      }
    }
    for (final member in members) {
      _cyclic[member] = cyclic;
      if (!_isLocal(member)) continue;
      final address = member.$2;
      if (cyclic) {
        engine._cyclic.add(address);
        engine._computed[address] = FormulaError.cycle;
      } else {
        engine._computed[address] = _evaluateLocal(address);
      }
    }
  }

  FormulaValue _evaluateLocal(CellAddress address) => formulaCellResult(
    engine.backend.evaluate(
      engine._asts[address]!,
      FormulaEvaluationContext(
        currentSheet: FormulaLookupSheet(engine._lookup),
        sheet: (reference) => _sheet(reference, null),
      ),
    ),
  );

  /// The sheet [reference] names, written in [holder] (null: the engine's own
  /// sheet).
  FormulaSheet _sheet(String reference, FormulaSheetTarget? holder) {
    final references = holder?.references ?? engine.references;
    if (holder == null) {
      final name = references.nameOf(reference);
      if (name == null) return const FormulaUnresolvedSheet();
      if (engine._isSelf(name)) return FormulaLookupSheet(engine._lookup);
    }
    final target = _resolve(reference, references);
    if (target == null) return const FormulaUnresolvedSheet();
    // The origin's own sheet is the live one, edits and all — and every cell
    // of it a formula here can reach is settled before that formula runs.
    if (target.id == engine.selfId) return FormulaLookupSheet(engine._lookup);
    return FormulaLookupSheet((address) => _remoteCell(target, address));
  }

  FormulaValue _remoteCell(FormulaSheetTarget target, CellAddress address) {
    final cell = _cellsOf(target)?[address];
    if (cell == null) return FormulaBlank.instance;
    switch (cell.kind) {
      case FormulaCellKind.embedded:
        return FormulaEmbedded.instance;
      case FormulaCellKind.value:
        return formulaValueOfLiteral(cell.value);
      case FormulaCellKind.formula:
        final key = (target.id, address);
        final known = _remoteValues[key];
        if (known != null) return known;
        final ast = _remoteAst(key);
        final FormulaValue value;
        if (ast == null) {
          value = FormulaError.generic;
        } else if (_cyclicOf(key)) {
          value = FormulaError.cycle;
        } else {
          // Evaluated by the origin's backend, so a read of another sheet
          // never mixes two backends.
          value = formulaCellResult(
            engine.backend.evaluate(
              FormulaProgram(cell.formula!, ast),
              FormulaEvaluationContext(
                currentSheet: FormulaLookupSheet(
                  (local) => _remoteCell(target, local),
                ),
                sheet: (reference) => _sheet(reference, target),
              ),
            ),
          );
        }
        return _remoteValues[key] = value;
    }
  }
}

final class _Frame {
  _Frame(this.key, this.successors);

  final FormulaCellKey key;
  final List<FormulaCellKey> successors;
  int next = 0;
}

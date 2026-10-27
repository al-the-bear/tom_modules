/// One formula function library, several callers.
///
/// The claim is not "the evaluator and a script agree about `SUM`". It is that
/// they reach **the same object**. Agreement is what two implementations have
/// until the day they stop; identity is what one implementation is. The
/// catalog is a map of named functions, and this file asserts that the map is
/// the only route in.
library;

import 'package:tom_formula/tom_formula.dart';
import 'package:test/test.dart';

/// The catalog, written out rather than derived from the map under
/// test — a totality check against the map that defines it would be vacuous.
const _d7Catalog = {
  'SUM', 'AVERAGE', 'MIN', 'MAX', 'COUNT', 'COUNTA', //
  'ROUND', 'ABS', 'INT', 'MOD', 'SQRT', 'POWER', //
  'IF', 'AND', 'OR', 'NOT', //
  'CONCAT', 'LEN', 'UPPER', 'LOWER', 'TRIM', 'LEFT', 'RIGHT', 'MID',
};

CellAddress _a(String address) => CellAddress.parse(address);

/// A sheet with A1..A4 = 1, 2, text, empty and B1 = TRUE.
SheetEngine _engine() {
  return SheetEngine({
    _a('A1'): const FormulaCell.value(1),
    _a('A2'): const FormulaCell.value(2),
    _a('A3'): const FormulaCell.value('text'),
    _a('B1'): const FormulaCell.value(true),
  });
}

/// What the grid computes for [formula], as plain Dart — so the assertions
/// below compare the *answer*, which is what one library is about. An error stays a
/// [FormulaError]. The value's kind is `formula_value_test.dart`'s subject.
Object? _grid(String formula) {
  final engine = _engine();
  engine.setFormula(_a('Z1'), formula);
  return formulaValueToDart(engine.valueOf(_a('Z1')));
}

void main() {
  group('the catalog is one set of objects', () {
    test('it holds the whole catalog, and only it '
        '[0922]', () {
      expect(
        formulaCatalog.keys.toSet(),
        _d7Catalog,
        reason:
            'the library is the catalog — a name here that D7 does not '
            'list is a function the grid would accept and the spec does not '
            'define, and a name missing is one a document can write and '
            'nothing computes',
      );
      expect(formulaCatalog, hasLength(24));
    });

    test('every script member resolves to a catalog entry '
        '[0922]', () {
      // The rename table is the only mapping between the two vocabularies, so
      // the thing to check is that it lands: a member naming a function that
      // does not exist would answer #NAME? at run time, from a namespace that
      // advertised it.
      for (final entry in formulaScriptNames.entries) {
        expect(
          formulaCatalog.containsKey(entry.value),
          isTrue,
          reason:
              'script member `${entry.key}` names ${entry.value}, which '
              'the catalog does not have',
        );
      }
      for (final entry in formulaRangeAliases.entries) {
        expect(
          formulaCatalog.containsKey(entry.value),
          isTrue,
          reason: 'range alias `${entry.key}` names ${entry.value}',
        );
      }
      expect(
        formulaScriptNames.values.toSet(),
        _d7Catalog,
        reason:
            'and every catalog function is reachable from a script — a '
            'function the grid has and a script cannot call is the gap this '
            'item exists to close',
      );
    });

    test('the namespace hands back the catalog\'s own function '
        '[0922]', () {
      // The item's DONE-WHEN, stated as identity rather than as agreement.
      const namespace = FormulaNamespace();
      for (final name in _d7Catalog) {
        expect(
          identical(namespace.functionFor(name), formulaCatalog[name]),
          isTrue,
          reason:
              '$name reached through the namespace is not the same '
              'object the catalog holds',
        );
      }
      expect(namespace.functionFor('NOSUCHFN'), isNull);
    });

    test('the grid reaches it too, by the same key [0922]', () {
      // The third leg. A grid that had kept its own `switch` would still pass
      // the two tests above, so this one checks the *behaviour* is the
      // function's: call the catalog entry directly and compare with what the
      // sheet computes for the same formula.
      const namespace = FormulaNamespace();
      expect(_grid('=SUM(A1:A3)'), 3);
      expect(
        _dart(
          namespace.invoke('rangeSum', [
            [1, 2, 'text'],
          ]),
        ),
        3,
      );

      expect(_grid('=AVERAGE(A1:A2)'), 1.5);
      expect(_dart(namespace.invoke('average', [1, 2])), 1.5);

      expect(_grid('=CONCAT("a", 1)'), 'a1');
      expect(_dart(namespace.invoke('concat', ['a', 1])), 'a1');
    });

    test('an unknown name is #NAME? on both routes [0922]', () {
      const namespace = FormulaNamespace();
      expect(_grid('=NOSUCHFN(1)'), FormulaError.name);
      expect(_dart(namespace.invoke('nosuchfn', [1])), FormulaError.name);
      expect(
        namespace.call('NOSUCHFN', [const FormulaNumber(1)]),
        FormulaError.name,
      );
    });

    test('IF does not evaluate the branch it does not take '
        '[0922]', () {
      // The reason every catalog function takes thunks. A uniform eager
      // signature would need IF to grow a second, lazy implementation
      // somewhere — which is the duplication one library forbids.
      var taken = <String>[];
      FormulaValue thunk(String label, String value) {
        taken.add(label);
        return FormulaText(value);
      }

      final ifFn = formulaCatalog['IF']!;
      taken = [];
      expect(
        ifFn([
          () => FormulaBoolean.yes,
          () => thunk('then', 'T'),
          () => thunk('else', 'E'),
        ]),
        const FormulaText('T'),
      );
      expect(taken, ['then'], reason: 'the else branch was never called');

      taken = [];
      expect(
        ifFn([
          () => FormulaBoolean.no,
          () => thunk('then', 'T'),
          () => thunk('else', 'E'),
        ]),
        const FormulaText('E'),
      );
      expect(taken, ['else']);

      // An else-less IF whose condition is false yields false.
      expect(
        ifFn([() => FormulaBoolean.no, () => const FormulaText('T')]),
        FormulaBoolean.no,
      );
      expect(_grid('=IF(0, 1)'), isFalse);
    });

    test('the operators are the library\'s too [0922]', () {
      // Same argument as the catalog, one level down: the lowered form of
      // `a + b` is `formula.add(a, b)`, so a second implementation of `+` in
      // the evaluator is exactly the divergence the differential corpus exists to
      // catch.
      expect(formulaOperators.keys.toSet(), {
        '+',
        '-',
        '*',
        '/',
        '^',
        '&',
        '=',
        '<>',
        '<',
        '<=',
        '>',
        '>=',
      });
      expect(formulaUnaryOperators.keys.toSet(), {'-', '+'});

      expect(
        formulaOperators['+']!(const FormulaNumber(1), const FormulaNumber(2)),
        const FormulaNumber(3),
      );
      expect(_grid('=1+2'), 3);
      expect(
        formulaOperators['/']!(const FormulaNumber(1), const FormulaNumber(0)),
        FormulaError.div0,
      );
      expect(_grid('=1/0'), FormulaError.div0);
      expect(
        formulaOperators['&']!(const FormulaText('a'), FormulaBoolean.yes),
        const FormulaText('aTRUE'),
      );
      expect(_grid('=A1&B1'), '1TRUE');
    });

    test('the fifteen functions the catalog gained work [0922]', () {
      // The catalog lists 24; nine were implemented once. The rest were
      // `#NAME?` — a sheet could write them and nothing computed them. Each
      // semantic below is Excel's, and each is the one a naive
      // implementation gets wrong.
      expect(
        _grid('=COUNTA(A1:A4)'),
        3,
        reason: 'every non-empty cell, text included; the empty A4 is not',
      );
      expect(
        _grid('=INT(-1.5)'),
        -2,
        reason: 'floor, toward negative infinity — truncation would give -1',
      );
      expect(
        _grid('=MOD(-1, 3)'),
        2,
        reason: 'the sign of the divisor, as Excel; remainder() gives -1',
      );
      expect(_grid('=MOD(1, 0)'), FormulaError.div0);
      expect(_grid('=SQRT(9)'), 3);
      expect(
        _grid('=SQRT(-1)'),
        FormulaError.value,
        reason:
            'not NaN, which would flow into every consuming formula as a '
            'number and compare unequal to itself',
      );
      expect(_grid('=POWER(2, 10)'), 1024);
      expect(_grid('=AND(1, 1)'), isTrue);
      expect(_grid('=AND(1, 0)'), isFalse);
      expect(_grid('=OR(0, 1)'), isTrue);
      expect(_grid('=NOT(0)'), isTrue);
      expect(_grid('=LEN("abcd")'), 4);
      expect(_grid('=UPPER("aB")'), 'AB');
      expect(_grid('=LOWER("aB")'), 'ab');
      expect(_grid('=TRIM("  a  ")'), 'a');
      expect(_grid('=LEFT("abcd")'), 'a', reason: 'n defaults to 1');
      expect(_grid('=LEFT("abcd", 2)'), 'ab');
      expect(_grid('=RIGHT("abcd", 2)'), 'cd');
      expect(
        _grid('=MID("abcd", 2, 2)'),
        'bc',
        reason: 'start is 1-based, as Excel',
      );
      expect(
        _grid('=MID("abcd", 9, 2)'),
        '',
        reason: 'a start past the end is empty, not an error',
      );
      expect(
        _grid('=MID("abcd", 0, 2)'),
        FormulaError.value,
        reason: 'but a start below 1 is a mistake worth naming',
      );
    });

    test('`^` and POWER are one function [0922]', () {
      // The operator entry *is* the function, by identity.
      expect(identical(formulaOperators['^'], formulaPower), isTrue);

      // POWER's catalog entry cannot be the same object — it unwraps thunks
      // and checks its arity first — so the claim that it does not reimplement
      // exponentiation needs a behavioural discriminator rather than an
      // `identical`. The fractional exponent is one: the engine's previous
      // hand-rolled power loop refused it outright (`=2^0.5` was `#VALUE!`,
      // with a comment saying fractional powers would need `dart:math`), so a
      // second POWER would have had to implement it separately to agree here.
      expect(_grid('=2^0.5'), closeTo(1.4142135, 0.000001));
      expect(_grid('=POWER(2, 0.5)'), closeTo(1.4142135, 0.000001));
      expect(
        _grid('=POWER(-8, 0.5)'),
        FormulaError.value,
        reason:
            'and they agree on the ugly case too — pow() answers NaN '
            'here, which must not reach a cell as a number',
      );
    });

    test('aggregates skip text in a range and refuse it as a '
        'scalar [0922]', () {
      // Not an inconsistency: SUM skips a non-numeric cell *inside a
      // range* because the author selected an area, and refuses a non-numeric
      // *scalar* because the author named that cell.
      expect(_grid('=SUM(A1:A3)'), 3);
      expect(_grid('=SUM(A1, A3)'), FormulaError.value);
      expect(
        _grid('=AVERAGE(A3:A3)'),
        FormulaError.div0,
        reason:
            'an average over zero numbers has no answer, and 0 would be '
            'one',
      );
    });
  });
}

Object? _dart(FormulaValue value) => formulaValueToDart(value);

/// The sealed value hierarchy and the namespace surface.
///
/// * the error tokens are written in **one** place, which a source scan holds
///   rather than a comment promising it;
/// * the namespace carries the whole list — catalog, range aliases, operators
///   and constructors — and an operator propagates an error it is handed.
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_formula/tom_formula.dart';

void main() {
  group('the tokens', () {
    test('one mapping, both ways', () {
      expect(
        [for (final c in FormulaErrorCode.values) c.token],
        ['#DIV/0!', '#VALUE!', '#REF!', '#NAME?', '#CYCLE!', '#ERROR!'],
      );
      for (final c in FormulaErrorCode.values) {
        expect(FormulaErrorCode.fromToken(c.token), c);
      }
      expect(FormulaErrorCode.fromToken('#NOPE!'), isNull);
    });

    test('no lib/ file but formula_value.dart writes a token as '
        'a string literal — the corpus, which states expected tokens as data, '
        'aside', () {
      final literal = RegExp(
        r'''['"]#(DIV/0!|VALUE!|REF!|NAME\?|CYCLE!|ERROR!)['"]''',
      );
      final holders = <String>{};
      for (final file
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))
              .where(
                (f) => !f.path.contains(
                  '${Platform.pathSeparator}testing${Platform.pathSeparator}',
                ),
              )) {
        if (literal.hasMatch(file.readAsStringSync())) holders.add(file.path);
      }
      expect(holders, hasLength(1), reason: 'found in: $holders');
      expect(holders.single, endsWith('formula_value.dart'));
    });
  });

  group('the surface is complete', () {
    const namespace = FormulaNamespace();

    test('every member is in the namespace', () {
      const spec = {
        // catalog, under the rename table
        'sum', 'average', 'min', 'max', 'count', 'countA', 'round', 'abs',
        'intFloor', 'mod', 'sqrt', 'power', 'ifElse', 'and', 'or', 'not',
        'concat', 'len', 'upper', 'lower', 'trim', 'left', 'right', 'mid',
        // single-range aliases
        'rangeSum', 'rangeAverage', 'rangeMin', 'rangeMax', 'rangeCount',
        'rangeCountA',
        // operators
        'add', 'subtract', 'multiply', 'divide', 'concatenate', 'eq', 'ne',
        'lt', 'le', 'gt', 'ge', 'negate', 'unaryPlus',
        // literal constructors
        'number', 'text', 'boolean', 'blank', 'error',
      };
      expect(FormulaNamespace.memberNames.toSet(), spec);
    });

    test('operators are the library\'s, and propagate errors', () {
      expect(namespace.invoke('add', [1, 2]), const FormulaNumber(3));
      expect(namespace.invoke('divide', [1, 0]), FormulaError.div0);
      expect(namespace.invoke('negate', [4]), const FormulaNumber(-4));
      expect(namespace.invoke('ge', [2, 2]), FormulaBoolean.yes);
      expect(
        namespace.invoke('concatenate', ['a', true]),
        const FormulaText('aTRUE'),
      );
      // An error handed to an operator comes out as itself — not as the
      // #VALUE! a coercion of it would give.
      expect(namespace.invoke('add', [FormulaError.ref, 1]), FormulaError.ref);
      expect(
        namespace.invoke('concatenate', [FormulaError.name, 'x']),
        FormulaError.name,
      );
      expect(
        namespace.invoke('add', [1]),
        FormulaError.value,
        reason: 'an operator takes exactly two operands',
      );
    });

    test('the constructors build the variants', () {
      expect(namespace.invoke('number', [7]), const FormulaNumber(7));
      expect(namespace.invoke('text', ['x']), const FormulaText('x'));
      expect(namespace.invoke('boolean', [false]), FormulaBoolean.no);
      expect(namespace.invoke('blank', const []), FormulaBlank.instance);
      expect(namespace.invoke('error', ['#REF!']), FormulaError.ref);
      expect(namespace.invoke('error', ['cycle']), FormulaError.cycle);
      expect(namespace.invoke('error', ['nonsense']), FormulaError.value);
      expect(
        namespace.invoke('number', ['7']),
        FormulaError.value,
        reason: 'a constructor does not coerce',
      );
    });
  });
}

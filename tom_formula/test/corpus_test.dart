/// The conformance corpus under the native backend, and the corpus's own
/// coverage.
///
/// The native backend defines the semantics, so every row's native result must
/// equal its `expected`; a second backend is then held to native by its host
/// (the interpreting backend's suite runs the same corpus through both). The
/// coverage checks keep the corpus whole: a suite that runs every row is only
/// as good as the rows, and a deleted row would otherwise thin it silently.
library;

import 'package:test/test.dart';
import 'package:tom_formula/testing.dart';
import 'package:tom_formula/tom_formula.dart';

void main() {
  final corpus = FormulaCorpus.load();

  group(
    'CORPUS-1: the native backend computes every row\'s expected value',
    () {
      for (final row in corpus.cases) {
        test('${row.id} (${row.cls})', () {
          expect(
            corpus.evaluate(row, const NativeFormulaBackend()),
            row.expected,
          );
        });
      }
    },
  );

  group(
    'CORPUS-2: every row lowers over exactly `formula` and `currentSheet`',
    () {
      for (final row in corpus.cases) {
        final formula = row.formula;
        if (formula == null) continue;
        test(row.id, () {
          final lowered = formulaLowering.lower(formula);
          if (lowered == null) {
            // A source the grammar rejects is never lowered.
            expect(row.expected, const FormulaError(FormulaErrorCode.syntax));
            return;
          }
          // Strip string literals, then every identifier that is not a member
          // access must be one of the two free names.
          final code = lowered.replaceAll(RegExp(r"'(?:[^'\\]|\\.)*'"), "''");
          final free = RegExp(r'(?<![.\w])([A-Za-z_]\w*)')
              .allMatches(code)
              .map((m) => m.group(1)!)
              .where((name) => name != 'true' && name != 'false')
              .toSet();
          expect(
            free.difference({'formula', 'currentSheet', 'FormulaErrorCode'}),
            isEmpty,
            reason: '$formula lowered to $lowered',
          );
        });
      }
    },
  );

  group('CORPUS-3: the corpus covers what conformance requires', () {
    test('every one of the seven classes has rows', () {
      expect(corpus.cases.map((c) => c.cls).toSet(), {
        'catalog',
        'operator',
        'error',
        'coercion',
        'section',
        'reference',
        'short-circuit',
      });
    });

    test('every catalog function is called by a catalog row', () {
      final called = <String>{
        for (final row in corpus.cases.where((c) => c.cls == 'catalog'))
          for (final m in RegExp(r'([A-Za-z]+)\(').allMatches(row.formula!))
            m.group(1)!.toUpperCase(),
      };
      expect(formulaCatalog.keys.toSet().difference(called), isEmpty);
    });

    test('every single-range alias is exercised', () {
      final lowered = [
        for (final row in corpus.cases)
          if (row.formula != null) formulaLowering.lower(row.formula!),
      ].whereType<String>().join('\n');
      for (final alias in formulaRangeAliases.keys) {
        expect(lowered, contains('formula.$alias('), reason: alias);
      }
    });

    test('every operator is exercised by an operator row', () {
      final lowered = [
        for (final row in corpus.cases.where((c) => c.cls == 'operator'))
          formulaLowering.lower(row.formula!)!,
      ].join('\n');
      for (final member in [
        ...formulaOperatorNames.keys,
        ...formulaUnaryOperatorNames.keys,
        'power',
      ]) {
        expect(lowered, contains('formula.$member('), reason: member);
      }
    });

    test('every error token both originates and propagates', () {
      for (final code in FormulaErrorCode.values) {
        final kinds = {
          for (final row in corpus.cases.where((c) => c.cls == 'error'))
            if (row.expected == FormulaError(code)) row.kind,
        };
        expect(
          kinds,
          containsAll(['originates', 'propagates']),
          reason: code.token,
        );
      }
    });

    test('row ids are unique, and the data holds one row per case', () {
      expect(corpus.cases.map((c) => c.id).toSet().length, corpus.cases.length);
      expect((formulaCorpusData['cases']! as List).length, corpus.cases.length);
    });
  });
}

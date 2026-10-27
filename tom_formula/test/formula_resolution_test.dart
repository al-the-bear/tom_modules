/// The formula evaluator resolves through what it is handed, and through
/// nothing else.
///
/// The evaluator's resolver is the [FormulaEvaluationContext]: `currentSheet`
/// resolves an A1 identifier, and `sheet` resolves a reference to another
/// sheet. So the test drives [NativeFormulaBackend] with **stubs** for both and
/// asserts two things: that the stubs were asked for exactly the addresses the
/// formula names, and that the values they answered are the values the formula
/// computed. A backend that read a cell any other way — a cached grid, a sheet
/// it found by itself — would either ask for the wrong addresses or compute a
/// value the stubs did not decide.
library;

import 'package:tom_formula/tom_formula.dart';
import 'package:test/test.dart';

/// A [FormulaLookupSheet] over a fixed table that records every address read.
final class _RecordingSheet {
  final Map<String, FormulaValue> cells;
  final List<String> asked = [];

  _RecordingSheet(this.cells);

  late final FormulaLookupSheet sheet = FormulaLookupSheet((address) {
    final a1 = address.encode();
    asked.add(a1);
    return cells[a1] ?? FormulaBlank.instance;
  });
}

void main() {
  const backend = NativeFormulaBackend();

  FormulaValue run(String source, FormulaEvaluationContext context) => backend
      .evaluate(FormulaProgram(source, FormulaParser.parse(source)), context);

  group('— the evaluator resolves through the injected context', () {
    late _RecordingSheet own;
    late _RecordingSheet remote;
    late List<String> references;
    late FormulaEvaluationContext context;

    setUp(() {
      own = _RecordingSheet({
        'A1': const FormulaNumber(3),
        'B1': const FormulaNumber(5),
        'A2': const FormulaNumber(7),
        'B2': const FormulaNumber(11),
      });
      remote = _RecordingSheet({'C3': const FormulaNumber(100)});
      references = [];
      context = FormulaEvaluationContext(
        currentSheet: own.sheet,
        sheet: (reference) {
          references.add(reference);
          return remote.sheet;
        },
      );
    });

    test('=A1+B2 reads A1 and B2 from the current sheet, and '
        'nothing else', () {
      expect(run('=A1+B2', context), const FormulaNumber(14));
      expect(own.asked, ['A1', 'B2']);
      expect(
        references,
        isEmpty,
        reason: 'no reference, so the resolver is never consulted',
      );
      expect(remote.asked, isEmpty);
    });

    test('=SUM(A1:B2) reads the four cells of the rectangle', () {
      expect(run('=SUM(A1:B2)', context), const FormulaNumber(26));
      expect(own.asked, unorderedEquals(['A1', 'B1', 'A2', 'B2']));
      expect(own.asked, hasLength(4), reason: 'each cell exactly once');
      expect(references, isEmpty);
    });

    test('a cross-section reference goes to the resolver with '
        'its reference string, and the resolved sheet answers', () {
      const ref = '#11111111-1111-4111-8111-111111111111';
      expect(run("='$ref'!C3*2+A1", context), const FormulaNumber(203));
      expect(references, [ref]);
      expect(remote.asked, ['C3']);
      expect(own.asked, [
        'A1',
      ], reason: 'the unqualified address still reads the current sheet');
    });

    test('the stubs decide the result — change the answers and '
        'the same programs compute different values', () {
      own.cells
        ..['A1'] = const FormulaNumber(-1)
        ..['B2'] = const FormulaText('x');
      remote.cells['C3'] = FormulaError.ref;

      expect(
        run('=A1+B2', context),
        FormulaError.value,
        reason: 'text in arithmetic is #VALUE!, decided by the stub value',
      );
      expect(
        run('=SUM(A1:B2)', context),
        const FormulaNumber(11),
        reason: 'SUM skips text: -1 + 5 + 7',
      );
      expect(
        run("='#elsewhere'!C3", context),
        FormulaError.ref,
        reason: 'the resolved sheet\'s error propagates as-is',
      );
      expect(references, ['#elsewhere']);
    });

    test('a reference the resolver cannot place answers #REF! '
        'through the resolver, not around it', () {
      final unresolved = FormulaEvaluationContext(
        currentSheet: own.sheet,
        sheet: (reference) {
          references.add(reference);
          return const FormulaUnresolvedSheet();
        },
      );
      expect(run("='#nowhere'!A1+1", unresolved), FormulaError.ref);
      expect(references, ['#nowhere']);
      expect(own.asked, isEmpty);
    });
  });
}

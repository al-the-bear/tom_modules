/// The lowering table, the source-keyed memo, the evaluation port with its
/// native default, and the scheduler around the port.
///
/// The second backend, which interprets the lowered form, lives with an
/// interpreter outside this package; this file proves the engine is whole
/// without one.
library;

import 'dart:io';

import 'package:tom_formula/tom_formula.dart';
import 'package:test/test.dart';

const _uuid = 'a91e0000-0000-4000-8000-000000000001';
const _book = '../budget.webwork#7f3c0000-0000-4000-8000-000000000002';

String? lower(String source) => FormulaLowering().lower(source);

CellAddress at(String a1) => CellAddress.parse(a1);

/// A backend that answers through native and counts its calls — proof that
/// the scheduler goes through the port rather than around it.
final class _CountingBackend implements FormulaEvaluationBackend {
  int calls = 0;

  @override
  String get id => 'counting';

  @override
  FormulaValue evaluate(
    FormulaProgram program,
    FormulaEvaluationContext context,
  ) {
    calls++;
    return const NativeFormulaBackend().evaluate(program, context);
  }
}

void main() {
  group('the worked examples, verbatim', () {
    const examples = {
      '=SUM(A1:C3)': 'formula.rangeSum(currentSheet.range(0, 0, 2, 2))',
      '=A1*2': 'formula.multiply(currentSheet.cell(0, 0), formula.number(2))',
      '=SUM(A1, B2:C3, 5)':
          'formula.sum([currentSheet.cell(0, 0), '
          'currentSheet.range(1, 1, 2, 2), formula.number(5)])',
      '=IF(A1>0, "ok", B1/0)':
          'formula.ifElse(formula.gt('
          'currentSheet.cell(0, 0), formula.number(0)), () => '
          "formula.text('ok'), () => formula.divide(currentSheet.cell(0, 1), "
          'formula.number(0)))',
      r'=$A$1 & " " & UPPER(B2)':
          'formula.concatenate(formula.concatenate('
          "currentSheet.cell(0, 0), formula.text(' ')), "
          'formula.upper(currentSheet.cell(1, 1)))',
      "='#$_uuid'!B2 * 2":
          "formula.multiply(formula.sheet('#$_uuid')"
          '.cell(1, 1), formula.number(2))',
      '=ROUND(AVERAGE(A1:A9), 2)':
          'formula.round(formula.rangeAverage('
          'currentSheet.range(0, 0, 8, 0)), formula.number(2))',
    };
    for (final MapEntry(:key, :value) in examples.entries) {
      test(key, () => expect(lower(key), value));
    }
  });

  group('references', () {
    test('the four absoluteness forms lower identically', () {
      final forms = [r'=A1', r'=$A1', r'=A$1', r'=$A$1'].map(lower).toSet();
      expect(forms, {'currentSheet.cell(0, 0)'});
      expect(lower(r'=SUM($A$1:C$3)'), lower('=SUM(A1:C3)'));
    });

    test('indices are zero-based; the 27th column is index 26', () {
      expect(lower('=AA1'), 'currentSheet.cell(0, 26)');
      expect(lower('=B10'), 'currentSheet.cell(9, 1)');
    });

    test('a cross-document locator is emitted verbatim', () {
      expect(
        lower("=SUM('$_book'!A1:A9)"),
        "formula.rangeSum(formula.sheet('$_book').range(0, 0, 8, 0))",
      );
    });
  });

  group('operators, literals and names', () {
    test('operators lower to calls; ^ and POWER are one function', () {
      expect(
        lower('=2^3'),
        'formula.power(formula.number(2), formula.number(3))',
      );
      expect(
        lower('=POWER(2,3)'),
        'formula.power(formula.number(2), formula.number(3))',
      );
      expect(lower('=-A1'), 'formula.negate(currentSheet.cell(0, 0))');
      expect(lower('=+A1'), 'formula.unaryPlus(currentSheet.cell(0, 0))');
      expect(
        lower('=(1+2)*3'),
        'formula.multiply(formula.add('
        'formula.number(1), formula.number(2)), formula.number(3))',
      );
    });

    test('text is D7-unescaped, then Dart-escaped', () {
      expect(lower('="a""b"'), '''formula.text('a"b')''');
      expect(lower(r'''="it's $x\"'''), r"formula.text('it\'s \$x\\')");
    });

    test('booleans, numbers and error literals', () {
      expect(lower('=TRUE'), 'formula.boolean(true)');
      expect(lower('=3.5'), 'formula.number(3.5)');
      expect(lower('=#REF!'), 'formula.error(FormulaErrorCode.ref)');
      expect(lower('=#DIV/0!'), 'formula.error(FormulaErrorCode.divideByZero)');
    });

    test('the renamed functions, and IF thunks every branch', () {
      expect(lower('=INT(A1)'), 'formula.intFloor(currentSheet.cell(0, 0))');
      expect(
        lower('=IF(A1,1)'),
        'formula.ifElse(currentSheet.cell(0, 0), () => formula.number(1))',
      );
    });

    test('an aggregate over anything but one range takes the list form', () {
      expect(lower('=SUM(A1)'), 'formula.sum([currentSheet.cell(0, 0)])');
      expect(
        lower('=COUNTA(A1:A2,B1)'),
        'formula.countA(['
        'currentSheet.range(0, 0, 1, 0), currentSheet.cell(0, 1)])',
      );
      expect(
        lower('=AND(TRUE,FALSE)'),
        'formula.and([formula.boolean(true), '
        'formula.boolean(false)])',
      );
    });

    test('an unknown name is #NAME? and never reaches the output', () {
      final lowered = lower('=EVIL(A1)')!;
      expect(lowered, 'formula.error(FormulaErrorCode.name)');
      expect(lowered, isNot(contains('EVIL')));
    });

    test('a source the grammar rejects is never lowered', () {
      expect(lower('=1+'), isNull);
      expect(lower('=SUM(('), isNull);
    });
  });

  group('the memo', () {
    test('keyed by source; \$A\$1 and A1 are separate entries', () {
      final memo = FormulaLowering();
      memo.lower(r'=$A$1');
      memo.lower('=A1');
      expect(memo.length, 2);
      expect(memo.lower(r'=$A$1'), memo.lower('=A1'));
      expect(memo.length, 2);
    });

    test('bounded LRU: the least recently used entry is evicted', () {
      final memo = FormulaLowering(capacity: 2);
      memo.lower('=1');
      memo.lower('=2');
      memo.lower('=1'); // =1 is now the most recent
      memo.lower('=3');
      expect(memo.holds('=1'), isTrue);
      expect(memo.holds('=2'), isFalse);
      expect(memo.holds('=3'), isTrue);
      memo.capacity = 1;
      expect(memo.length, 1);
    });

    test('the default capacity is 4096', () {
      expect(FormulaLowering.defaultCapacity, 4096);
      expect(formulaLowering.capacity, 4096);
    });
  });

  group('the lowered form is read only by the port', () {
    test('no lib file writes the lowered form anywhere but the memo', () {
      final offenders = <String>[];
      for (final file
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        if (file.path.endsWith('formula_lowering.dart') ||
            file.path.endsWith('formula_backend.dart')) {
          continue;
        }
        if (file.readAsStringSync().contains('.lowered'))
          offenders.add(file.path);
      }
      expect(
        offenders,
        isEmpty,
        reason: 'only the port reads FormulaProgram.lowered',
      );
    });
  });

  group('the port and its native default', () {
    test('the process backend is native unless a root chose another', () {
      expect(formulaBackend, isA<NativeFormulaBackend>());
      expect(formulaBackend.id, 'native');
    });

    test('the scheduler evaluates every formula cell through the port', () {
      final backend = _CountingBackend();
      final engine = SheetEngine({
        at('A1'): FormulaCell.value(1),
        at('B1'): FormulaCell.formula('=A1+1'),
        at('C1'): FormulaCell.formula('=B1*2'),
      }, backend: backend);
      expect(engine.valueOf(at('C1')), const FormulaNumber(4));
      expect(backend.calls, 2);
      engine.setValue(at('A1'), 5);
      expect(backend.calls, 4, reason: 'exactly the two dependents');
      expect(engine.valueOf(at('C1')), const FormulaNumber(12));
    });

    test('useFormulaBackend sets the process backend', () {
      final backend = _CountingBackend();
      useFormulaBackend(backend);
      addTearDown(() => useFormulaBackend(const NativeFormulaBackend()));
      SheetEngine({at('A1'): FormulaCell.formula('=1')});
      expect(backend.calls, 1);
    });
  });

  group('the scheduler around the port', () {
    test('a formula the grammar rejects is #ERROR!, not a crash', () {
      final engine = SheetEngine({
        at('A1'): FormulaCell.formula('=1+'),
        at('B1'): FormulaCell.formula('=A1*2'),
      });
      expect(engine.valueOf(at('A1')), FormulaError.generic);
      expect(engine.valueOf(at('B1')), FormulaError.generic);
      engine.setFormula(at('A1'), '=(');
      expect(engine.valueOf(at('A1')), FormulaError.generic);
      engine.setFormula(at('A1'), '=3');
      expect(engine.valueOf(at('B1')), const FormulaNumber(6));
    });

    test('both IF branches are dependencies', () {
      final engine = SheetEngine({
        at('A1'): FormulaCell.value(true),
        at('B1'): FormulaCell.value(1),
        at('C1'): FormulaCell.value(2),
        at('D1'): FormulaCell.formula('=IF(A1,B1,C1)'),
      });
      expect(engine.dependentsOf(at('C1')), contains(at('D1')));
      engine.setValue(at('A1'), false);
      expect(engine.valueOf(at('D1')), const FormulaNumber(2));
      engine.setValue(at('C1'), 7);
      expect(engine.valueOf(at('D1')), const FormulaNumber(7));
    });

    test('a range is never a cell value', () {
      final engine = SheetEngine({
        at('A1'): FormulaCell.value(1),
        at('B1'): FormulaCell.formula('=IF(TRUE,A1:A2,0)'),
      });
      expect(engine.valueOf(at('B1')), FormulaError.value);
    });

    test('a sheet read is scalar through cell and raw through range', () {
      final engine = SheetEngine({
        at('A1'): const FormulaCell.embedded('an embedded object'),
      });
      expect(engine.cell(0, 0), FormulaError.value);
      expect(
        engine.range(0, 0, 0, 0),
        const FormulaRange([FormulaEmbedded.instance]),
      );
    });
  });
}

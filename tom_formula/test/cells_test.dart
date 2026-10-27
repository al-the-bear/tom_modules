/// The cell model: addresses and the exactly-one-of cell.
library;

import 'package:test/test.dart';
import 'package:tom_formula/tom_formula.dart';

void main() {
  group('CellAddress', () {
    test('parses and encodes A1 addresses, AA after Z', () {
      expect(CellAddress.parse('B12'), const CellAddress(1, 12));
      expect(CellAddress.parse('AA1').column, 26);
      expect(const CellAddress(27, 3).encode(), 'AB3');
      expect(CellAddress.lettersFromColumnIndex(701), 'ZZ');
      expect(CellAddress.columnIndexFromLetters('ZZ'), 701);
    });

    test('refuses what is not an address', () {
      for (final bad in ['', 'A0', '1A', 'a1', r'$A$1', 'A1:B2']) {
        expect(
          () => CellAddress.parse(bad),
          throwsFormatException,
          reason: bad,
        );
      }
    });

    test('orders column first, then row', () {
      final sorted = [
        CellAddress.parse('B1'),
        CellAddress.parse('A2'),
        CellAddress.parse('A1'),
      ]..sort();
      expect(sorted.map((a) => a.encode()), ['A1', 'A2', 'B1']);
    });
  });

  group('FormulaCell', () {
    test('holds exactly one thing, and says which', () {
      expect(const FormulaCell.value(1).kind, FormulaCellKind.value);
      expect(const FormulaCell.value(null).kind, FormulaCellKind.value);
      expect(FormulaCell.formula('=1').kind, FormulaCellKind.formula);
      expect(const FormulaCell.embedded('x').kind, FormulaCellKind.embedded);
    });

    test('a formula starts with "="', () {
      expect(() => FormulaCell.formula('1+1'), throwsFormatException);
    });

    test('sameAs compares kind and content, the literal\'s type included', () {
      expect(
        const FormulaCell.value(1).sameAs(const FormulaCell.value(1)),
        isTrue,
      );
      expect(
        const FormulaCell.value(1).sameAs(const FormulaCell.value(1.0)),
        isFalse,
      );
      expect(
        FormulaCell.formula('=A1').sameAs(FormulaCell.formula('=A1')),
        isTrue,
      );
      expect(
        const FormulaCell.embedded('x').sameAs(const FormulaCell.value('x')),
        isFalse,
      );
      expect(const FormulaCell.value(1).sameAs(null), isFalse);
    });

    test('an embedded cell has no scalar value', () {
      final engine = SheetEngine({
        CellAddress.parse('A1'): const FormulaCell.embedded('a picture'),
        CellAddress.parse('B1'): FormulaCell.formula('=A1+1'),
        CellAddress.parse('C1'): FormulaCell.formula('=COUNTA(A1:A1)'),
      });
      expect(engine.valueOf(CellAddress.parse('A1')), FormulaEmbedded.instance);
      expect(engine.valueOf(CellAddress.parse('B1')), FormulaError.value);
      expect(engine.valueOf(CellAddress.parse('C1')), const FormulaNumber(0));
    });
  });
}

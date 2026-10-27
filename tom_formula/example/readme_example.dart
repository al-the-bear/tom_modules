// The README example, compiled: a sheet with formulas, an edit that
// recalculates its dependents, a read of another sheet through a
// resolver, and a formula's lowered Dart form.
import 'package:tom_formula/tom_formula.dart';

/// Sheets by name; every reference is local.
class Workbook implements FormulaReferenceResolver {
  Workbook(this.sheets);

  final Map<String, Map<CellAddress, FormulaCell>> sheets;

  @override
  FormulaSheetName? nameOf(String reference) =>
      FormulaSheetName(reference, local: true);

  @override
  FormulaSheetTarget? resolve(String reference) {
    final cells = sheets[reference];
    if (cells == null) return null;
    return FormulaSheetTarget(
      id: reference,
      references: this,
      cells: () => cells,
    );
  }
}

void main() {
  CellAddress at(String a1) => CellAddress.parse(a1);

  final rates = {at('A1'): const FormulaCell.value(0.2)};
  final book = Workbook({'rates': rates});

  final engine = SheetEngine(
    {
      at('A1'): const FormulaCell.value(120),
      at('A2'): const FormulaCell.value(80),
      at('A3'): FormulaCell.formula('=SUM(A1:A2)'),
      at('A4'): FormulaCell.formula("=A3*'rates'!A1"),
      at('A5'): FormulaCell.formula('=IF(A4>50,"high","low")'),
    },
    selfId: 'invoice',
    references: book,
  );
  print(engine.valueOf(at('A3')).display);
  print(engine.valueOf(at('A4')).display);
  print(engine.valueOf(at('A5')).display);

  engine.setValue(at('A2'), 30);
  print(engine.valueOf(at('A3')).display);
  print(engine.valueOf(at('A5')).display);

  engine.setFormula(at('A6'), '=1/0');
  print(engine.valueOf(at('A6')).display);

  print(formulaLowering.lower("=SUM(A1:A2)+'rates'!A1"));
}

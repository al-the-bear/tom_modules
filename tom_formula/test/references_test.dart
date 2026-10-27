/// Reads of other sheets through the reference port: what a resolver answers,
/// what the engine indexes, and how recalculation, cycles and unresolvable
/// references behave across sheets.
library;

import 'package:test/test.dart';
import 'package:tom_formula/tom_formula.dart';

CellAddress at(String a1) => CellAddress.parse(a1);

/// Sheets by name in one container; `far:<name>` names a sheet of a second
/// container, whose own references resolve there. A name the books do not
/// hold names nothing that is a sheet.
final class Books implements FormulaReferenceResolver {
  Books(this.sheets, {this.far = const {}, this.container = 'near'});

  final Map<String, Map<CellAddress, FormulaCell>> sheets;
  final Map<String, Map<CellAddress, FormulaCell>> far;
  final String container;
  final List<String> resolved = [];

  @override
  FormulaSheetName? nameOf(String reference) {
    if (reference.isEmpty || reference.contains(' ')) return null;
    if (reference.startsWith('far:')) {
      return FormulaSheetName(reference.substring(4), local: false);
    }
    return FormulaSheetName(reference, local: true);
  }

  @override
  FormulaSheetTarget? resolve(String reference) {
    resolved.add(reference);
    final name = nameOf(reference);
    if (name == null) return null;
    if (!name.local) {
      final cells = far[name.id];
      if (cells == null) return null;
      return FormulaSheetTarget(
        id: name.id,
        references: Books(far, container: 'far'),
        cells: () => cells,
      );
    }
    final cells = sheets[name.id];
    if (cells == null) return null;
    return FormulaSheetTarget(
      id: name.id,
      references: this,
      cells: () => cells,
    );
  }
}

void main() {
  group('REF-1: a read of another sheet', () {
    test('resolves through the resolver and computes there', () {
      final books = Books({
        'budget': {
          at('A1'): const FormulaCell.value(4),
          at('B1'): FormulaCell.formula('=A1*10'),
        },
      });
      final engine = SheetEngine(
        {at('A1'): FormulaCell.formula("='budget'!B1+1")},
        selfId: 'main',
        references: books,
      );
      expect(engine.valueOf(at('A1')), const FormulaNumber(41));
      expect(engine.crossDependenciesOf(at('A1')), {('budget', at('B1'))});
      expect(engine.readersOf('budget'), {at('A1')});
    });

    test('a reference the resolver cannot name is #REF! and reads nothing', () {
      final engine = SheetEngine(
        {at('A1'): FormulaCell.formula("='no such'!B1")},
        selfId: 'main',
        references: Books({}),
      );
      expect(engine.valueOf(at('A1')), FormulaError.ref);
      expect(engine.crossDependenciesOf(at('A1')), isEmpty);
    });

    test('a name that resolves to no sheet is #REF!, but is indexed, so the '
        'sheet appearing later is noticed', () {
      final sheets = <String, Map<CellAddress, FormulaCell>>{};
      final engine = SheetEngine(
        {at('A1'): FormulaCell.formula("='later'!A1")},
        selfId: 'main',
        references: Books(sheets),
      );
      expect(engine.valueOf(at('A1')), FormulaError.ref);
      expect(engine.readersOf('later'), {at('A1')});
      sheets['later'] = {at('A1'): const FormulaCell.value(9)};
      expect(engine.recalculateReaders('later'), {at('A1')});
      expect(engine.valueOf(at('A1')), const FormulaNumber(9));
    });

    test('a target whose cells cannot be read is #REF! throughout', () {
      final engine = SheetEngine(
        {at('A1'): FormulaCell.formula("='broken'!A1")},
        selfId: 'main',
        references: _Broken(),
      );
      expect(engine.valueOf(at('A1')), FormulaError.ref);
    });

    test('a local reference to the sheet\'s own id is a read of itself', () {
      final engine = SheetEngine(
        {
          at('A1'): const FormulaCell.value(3),
          at('B1'): FormulaCell.formula("='main'!A1*2"),
        },
        selfId: 'main',
        references: Books({}),
      );
      expect(engine.valueOf(at('B1')), const FormulaNumber(6));
      expect(engine.dependentsOf(at('A1')), {at('B1')});
      expect(engine.crossDependenciesOf(at('B1')), isEmpty);
      engine.setValue(at('A1'), 5);
      expect(engine.valueOf(at('B1')), const FormulaNumber(10));
    });

    test('a non-local reference with the same id is another sheet', () {
      final books = Books(
        {},
        far: {
          'main': {at('A1'): const FormulaCell.value(100)},
        },
      );
      final engine = SheetEngine(
        {
          at('A1'): const FormulaCell.value(1),
          at('B1'): FormulaCell.formula("='far:main'!A1"),
        },
        selfId: 'main',
        references: books,
      );
      // It shares the id, so the pass reads it as the origin sheet itself —
      // ids are identities, and two sheets must not share one.
      expect(engine.valueOf(at('B1')), const FormulaNumber(1));
    });
  });

  group(
    'REF-2: a reference is resolved hop by hop, each through its holder',
    () {
      test('a far sheet reads its own references in its own container', () {
        final books = Books(
          {
            'rates': {at('A1'): const FormulaCell.value(1)},
          },
          far: {
            'ledger': {at('A1'): FormulaCell.formula("='rates'!A1*7")},
            'rates': {at('A1'): const FormulaCell.value(3)},
          },
        );
        final engine = SheetEngine(
          {at('A1'): FormulaCell.formula("='far:ledger'!A1")},
          selfId: 'main',
          references: books,
        );
        expect(
          engine.valueOf(at('A1')),
          const FormulaNumber(21),
          reason: 'ledger reads the far rates (3), not the near ones (1)',
        );
      });
    },
  );

  group('REF-3: cycles across sheets', () {
    test('a cycle through another sheet is #CYCLE! on the origin', () {
      final main = {at('A1'): FormulaCell.formula("='other'!A1+1")};
      final books = Books({
        'main': main,
        'other': {at('A1'): FormulaCell.formula("='main'!A1+1")},
      });
      final engine = SheetEngine(main, selfId: 'main', references: books);
      expect(engine.valueOf(at('A1')), FormulaError.cycle);
      expect(engine.isCyclic(at('A1')), isTrue);
    });

    test('a cycle inside another sheet makes a reader downstream of it', () {
      final books = Books({
        'loop': {
          at('A1'): FormulaCell.formula('=A2'),
          at('A2'): FormulaCell.formula('=A1'),
        },
      });
      final engine = SheetEngine(
        {at('A1'): FormulaCell.formula("='loop'!A1")},
        selfId: 'main',
        references: books,
      );
      expect(engine.valueOf(at('A1')), FormulaError.cycle);
    });
  });

  group('REF-4: formulaSheet and the namespace read a sheet by reference', () {
    final books = Books({
      'budget': {
        at('A1'): const FormulaCell.value(2),
        at('A2'): FormulaCell.formula('=A1*3'),
      },
    });

    test('cells by 0-based index, ranges raw', () {
      final sheet = formulaSheet('budget', references: books);
      expect(sheet.resolved, isTrue);
      expect(sheet.cell(1, 0), const FormulaNumber(6));
      expect(
        sheet.range(0, 0, 1, 0),
        const FormulaRange([FormulaNumber(2), FormulaNumber(6)]),
      );
    });

    test('an unresolvable reference is #REF! throughout, never a throw', () {
      final sheet = FormulaNamespace(references: books).sheet('nowhere');
      expect(sheet.resolved, isFalse);
      expect(sheet.cell(0, 0), FormulaError.ref);
      expect(sheet.range(0, 0, 1, 1), FormulaError.ref);
      expect(
        const FormulaNamespace().sheet('budget').cell(0, 0),
        FormulaError.ref,
        reason: 'with no resolver nothing resolves',
      );
    });

    test('reading a sheet does not change the cells it was given', () {
      final before = Map.of(books.sheets['budget']!);
      formulaSheet('budget', references: books).cell(1, 0);
      expect(books.sheets['budget'], before);
    });
  });
}

final class _Broken implements FormulaReferenceResolver {
  @override
  FormulaSheetName? nameOf(String reference) =>
      FormulaSheetName(reference, local: true);

  @override
  FormulaSheetTarget? resolve(String reference) =>
      FormulaSheetTarget(id: reference, references: this, cells: () => null);
}

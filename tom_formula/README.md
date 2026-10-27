# tom_formula

Published on pub.dev as [`tom_formula` 0.1.0](https://pub.dev/packages/tom_formula).

> **Attribution.** The Tom Framework is developed by Peter Nicolai Alexis Kyaw.
> These packages are BSD-3-Clause licensed and published on pub.dev.

A spreadsheet formula engine: an Excel-style grammar and its printer, a library
of formula functions implemented once as plain Dart, recalculation that tracks
dependencies exactly — across sheets — and finds cycles structurally, lowering
of a formula to a Dart expression, and a port for the backend that evaluates
it. An application supplies its cells, and how a reference to another sheet
resolves; it gets computed values.

## Overview

- **Cells** (`FormulaCell`) hold exactly one of a literal, a formula with its
  leading `=`, or an **embedded** object the application owns — a document, an
  image, a nested sheet. An embedded cell has no scalar value: read as a
  scalar it is `#VALUE!`, and an aggregate over a range skips it.
- **Values** are a sealed hierarchy (`FormulaValue`: number, text, boolean,
  blank, embedded, range, error). Errors are values, so they propagate without
  aborting a recalculation, and the tokens (`#DIV/0!`, `#VALUE!`, `#REF!`,
  `#NAME?`, `#CYCLE!`, `#ERROR!`) are written in one place, `FormulaErrorCode`.
- **One function library, several callers.** The 24 catalog functions and the
  operators live in `formulaCatalog` and `formulaOperators` — maps of named
  functions rather than a `switch` — so the evaluator, a script's
  `FormulaNamespace` and a lowered expression reach the **same objects**.
  Arguments are thunks, which is what lets `IF` leave the branch it does not
  take unevaluated.
- **Recalculation** (`SheetEngine`) indexes every formula's reads: the cells
  of its own sheet, and `(sheetId, address)` pairs in other sheets. An edit
  recalculates exactly its transitive dependents; `recalculateReaders` carries
  an edit in another sheet to the cells that read it. Cycles are found by one
  Tarjan pass over the formula graph per recalculation, so every cell on or
  downstream of a cycle is `#CYCLE!` — including one whose `IF` would not have
  taken the branch that reaches it. The pass is linear, which keeps a cold load
  linear.
- **References to other sheets** are written `'name'!A1`. What the quoted
  string names is the application's: it implements `FormulaReferenceResolver`
  — what a reference names (`nameOf`, the key the engine indexes by) and the
  sheet it resolves to (`resolve`). A reference is relative to the sheet that
  holds it, so a chain of references resolves hop by hop through each holder's
  resolver. A reference that names nothing is `#REF!`.
- **Lowering** (`lowerFormula`, memoised in `FormulaLowering`) renders a
  formula as a Dart expression over exactly two free names, `formula` and
  `currentSheet`. It is total over parsed formulas, a pure function of the
  source, and never persisted. Dependencies are extracted from the AST before
  any lowering.
- **Backends** implement `FormulaEvaluationBackend`. The engine schedules and
  the backend only evaluates. `NativeFormulaBackend` walks the AST and is the
  default; a backend that interprets the lowered expression lives in a package
  that may name an interpreter. `useFormulaBackend` chooses the process's one.
- **Testing a backend.** `package:tom_formula/testing.dart` carries the
  conformance corpus (`FormulaCorpus`) — every row's expected value, which a
  second backend must match structurally — and the promotion-gate benchmark
  (`runFormulaPromotionGate`, gates G1–G5).

## Installation

Add it from pub.dev:

```yaml
dependencies:
  tom_formula: ^0.1.0
```

Dart SDK `^3.10.8`. The default entry point uses no Flutter and no `dart:io`,
so it links into a browser build; `testing.dart` uses `dart:io`.

## Features

| Type | What it does |
| ---- | ------------ |
| `CellAddress`, `FormulaCell`, `FormulaCellKind` | The cells an engine computes over. |
| `FormulaParser`, `FormulaNode` and its subtypes, `formulaSource` | The grammar, its AST, dependency extraction and the printer. |
| `rewriteFormulaReferences`, `formulaReferences`, `moveFormulaReference`, `CellRect` | Structural rewriting: moving references when rows or columns move. |
| `FormulaValue` and its variants, `FormulaErrorCode` | The values a formula computes. |
| `formulaCatalog`, `formulaOperators`, `formulaUnaryOperators`, `FormulaNamespace` | The function library and the surface a script calls. |
| `SheetEngine`, `FormulaCellKey` | Recalculation with dependency tracking and cycle detection. |
| `FormulaReferenceResolver`, `FormulaSheetName`, `FormulaSheetTarget`, `FormulaNoReferences`, `formulaSheet` | Reads of other sheets. |
| `lowerFormula`, `FormulaLowering`, `formulaLowering` | Lowering to Dart and its memo. |
| `FormulaEvaluationBackend`, `NativeFormulaBackend`, `FormulaProgram`, `FormulaEvaluationContext`, `FormulaSheet` | The backend port. |
| `FormulaCorpus`, `runFormulaPromotionGate` (`testing.dart`) | The conformance corpus and the promotion gate. |

## Example

```dart
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
```

The compiled form of this section is
[`example/readme_example.dart`](example/readme_example.dart), and
`test/readme_example_test.dart` asserts what it prints.

## Dependencies

| Dependency | Kind | For |
| ---------- | ---- | --- |
| `meta` | runtime | `@visibleForTesting` |
| `test`, `lints` | dev | the suite |

## Status

Version **0.1.0**. `dart test` runs the suite: the cell model, the grammar and
lowering, the function library, values and the namespace surface, reads of
other sheets and cycles across them, the conformance corpus under the native
backend, the benchmark harness, the package's shape, and the example.

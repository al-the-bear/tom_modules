# Changelog

## 0.1.0

The package was `tom_core_formula` in the `tom_core` repository; it is now
`tom_formula` in `tom_modules`, with the barrel
`package:tom_formula/tom_formula.dart` and `testing.dart`. Type names are
unchanged.

### Added

- **Cells.** `CellAddress`, `FormulaCell` (a literal, a formula or an embedded
  object) and `FormulaCellKind`.
- **The grammar.** `FormulaParser` and its AST, dependency extraction within a
  sheet and across sheets, the printer `formulaSource`, and structural
  rewriting (`rewriteFormulaReferences`, `moveFormulaReference`, `CellRect`).
- **Values.** The sealed `FormulaValue` hierarchy and `FormulaErrorCode`, the
  one place the error tokens are written.
- **The function library.** `formulaCatalog` (24 functions), the operators,
  the coercion rules, and `FormulaNamespace`, the surface a script calls.
- **Recalculation.** `SheetEngine`: exact dependency tracking, one Tarjan pass
  per recalculation for cycles across sheets, and reads of other sheets
  through a `FormulaReferenceResolver`.
- **Lowering and backends.** `lowerFormula` with the `FormulaLowering` memo,
  the `FormulaEvaluationBackend` port and `NativeFormulaBackend`.
- **Testing.** `package:tom_formula/testing.dart`: the conformance corpus
  every backend must agree with native on, and the promotion-gate benchmark.

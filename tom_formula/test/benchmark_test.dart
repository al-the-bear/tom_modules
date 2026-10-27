/// The promotion-gate harness, run small. At full scale it is a measurement a
/// host runs as a tool; this keeps the harness honest.
library;

import 'package:test/test.dart';
import 'package:tom_formula/testing.dart';
import 'package:tom_formula/tom_formula.dart';

void main() {
  test(
    'BENCH-1: the gate measures candidate and control and judges G1–G5',
    () async {
      final report = await runFormulaPromotionGate(
        const NativeFormulaBackend(),
        differentialGreen: true,
        workload: const FormulaWorkload(chains: 10, depth: 12, edits: 20),
      );
      expect(report.native.backend, 'native');
      expect(report.candidate.checksum, report.native.checksum);
      expect(report.native.checksum, isA<FormulaNumber>());
      expect(report.candidate.edits, hasLength(20));
      expect(report.gates.map((g) => g.gate), ['G1', 'G2', 'G3', 'G4', 'G5']);
      expect(report.render(), contains('Verdict:'));
    },
  );

  test('BENCH-2: G5 fails when the corpus did not agree', () async {
    final report = await runFormulaPromotionGate(
      const NativeFormulaBackend(),
      differentialGreen: false,
      workload: const FormulaWorkload(chains: 2, depth: 3, edits: 2),
    );
    expect(report.gates.last.passed, isFalse);
    expect(report.promotable, isFalse);
  });

  test('BENCH-3: the gate workload is 10 000 formula cells, chains of depth '
      '100, 1 000 edits', () {
    expect(FormulaWorkload.gate.formulaCells, 10000);
    expect(FormulaWorkload.gate.depth, greaterThanOrEqualTo(100));
    expect(FormulaWorkload.gate.edits, 1000);
  });
}

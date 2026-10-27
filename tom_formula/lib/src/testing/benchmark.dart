/// The promotion gate for a formula backend, as a repeatable benchmark.
///
/// Runs the G1/G2 workloads under a candidate backend, with the native backend
/// measured in the same run as the control, and judges five gates: G1 cold
/// load, G2 edit latency, G3 the longest stop-the-world pause, G4 the ratio to
/// native, G5 agreement with native on the conformance corpus. A host runs it
/// at full scale as a tool and small in its suite, to keep the harness honest.
///
/// **G3 is measured, not inferred.** A stop-the-world collection — an
/// interpreter's failure mode under allocation pressure — parks every isolate
/// of the group at a safepoint. So a ticker
/// isolate in the same group records the longest gap between its own wake-ups
/// while the workload runs; a gap over the bound is a pause the user would have
/// seen. It is conservative: an OS descheduling the ticker also shows as a
/// gap, so a failure names the gap without claiming it was a collection.
library;

import 'dart:io';
import 'dart:isolate';

import '../cells.dart';
import '../formula_backend.dart';
import '../formula_engine.dart';
import '../formula_value.dart';

/// The workload's shape: [chains] rows, each a dependency chain of
/// [depth] formula cells over one seed value — `chains × depth` formula cells
/// and a chain depth of [depth].
final class FormulaWorkload {
  final int chains;
  final int depth;
  final int edits;

  const FormulaWorkload({
    this.chains = 100,
    this.depth = 100,
    this.edits = 1000,
  });

  /// G1's sheet: 10 000 formula cells, chains of depth 100.
  static const gate = FormulaWorkload();

  int get formulaCells => chains * depth;

  /// Column A holds the seeds; columns B… hold the chains. Each link mixes a
  /// cell read, an operator and a catalog call, so the workload exercises the
  /// paths a real sheet does rather than one operator in a loop.
  Map<CellAddress, FormulaCell> cells() {
    final cells = <CellAddress, FormulaCell>{};
    for (var r = 1; r <= chains; r++) {
      cells[CellAddress(0, r)] = FormulaCell.value(r);
      for (var c = 1; c <= depth; c++) {
        final previous = CellAddress(c - 1, r).encode();
        cells[CellAddress(c, r)] = FormulaCell.formula(
          c % 10 == 0
              ? '=IF($previous>0,ROUND($previous*1.01,2),0)'
              : '=$previous+1',
        );
      }
    }
    return cells;
  }
}

/// One backend's measurements.
final class FormulaMeasurement {
  final String backend;

  /// G1 — cold full recalculation on load.
  final Duration coldLoad;

  /// G2 — per-edit recalculation latencies, sorted ascending.
  final List<Duration> edits;

  /// G3 — the longest stop-the-world gap the ticker saw over the whole run.
  final Duration longestPause;

  /// The value at the end of the first chain — compared across backends so a
  /// fast wrong answer cannot pass.
  final FormulaValue checksum;

  const FormulaMeasurement({
    required this.backend,
    required this.coldLoad,
    required this.edits,
    required this.longestPause,
    required this.checksum,
  });

  Duration get median => _percentile(0.5);
  Duration get p99 => _percentile(0.99);

  Duration _percentile(double q) =>
      edits.isEmpty ? Duration.zero : edits[((edits.length - 1) * q).round()];
}

/// One gate's verdict.
final class FormulaGateResult {
  final String gate;
  final bool passed;
  final String detail;

  const FormulaGateResult(this.gate, this.passed, this.detail);
}

/// The whole report.
final class FormulaGateReport {
  final FormulaWorkload workload;
  final FormulaMeasurement native;
  final FormulaMeasurement candidate;
  final List<FormulaGateResult> gates;

  const FormulaGateReport(
    this.workload,
    this.native,
    this.candidate,
    this.gates,
  );

  /// Whether the candidate may be promoted to default: every gate.
  bool get promotable => gates.every((g) => g.passed);

  String render() {
    String ms(Duration d) =>
        '${(d.inMicroseconds / 1000).toStringAsFixed(2)} ms';
    final out = StringBuffer()
      ..writeln(
        'Formula backend promotion gate — ${candidate.backend} vs '
        '${native.backend} (control)',
      )
      ..writeln(
        'workload: ${workload.formulaCells} formula cells, chain '
        'depth ${workload.depth}, ${workload.edits} edits',
      )
      ..writeln()
      ..writeln('| measure | ${native.backend} | ${candidate.backend} |')
      ..writeln('| --- | --- | --- |')
      ..writeln(
        '| cold load | ${ms(native.coldLoad)} | ${ms(candidate.coldLoad)} |',
      )
      ..writeln(
        '| edit median | ${ms(native.median)} | ${ms(candidate.median)} |',
      )
      ..writeln('| edit p99 | ${ms(native.p99)} | ${ms(candidate.p99)} |')
      ..writeln(
        '| longest pause | ${ms(native.longestPause)} | '
        '${ms(candidate.longestPause)} |',
      )
      ..writeln();
    for (final gate in gates) {
      out.writeln(
        '${gate.passed ? 'PASS' : 'FAIL'} ${gate.gate} — ${gate.detail}',
      );
    }
    out
      ..writeln()
      ..writeln(
        promotable
            ? 'Verdict: ${candidate.backend} MAY be promoted to default.'
            : 'Verdict: ${candidate.backend} stays non-default; '
                  '${native.backend} remains the default.',
      );
    return out.toString();
  }
}

/// Measures [backend] on [workload].
Future<FormulaMeasurement> measureFormulaBackend(
  FormulaEvaluationBackend backend, {
  FormulaWorkload workload = FormulaWorkload.gate,
}) async {
  final ticker = await _PauseTicker.start();
  try {
    final cells = workload.cells();
    final cold = Stopwatch()..start();
    final engine = SheetEngine(cells, backend: backend);
    cold.stop();

    final edits = <Duration>[];
    for (var i = 0; i < workload.edits; i++) {
      // A deterministic walk over the seeds, so two backends edit the same
      // cells in the same order.
      final row = (i * 37) % workload.chains + 1;
      final watch = Stopwatch()..start();
      engine.setValue(CellAddress(0, row), i + 1);
      watch.stop();
      edits.add(watch.elapsed);
    }
    edits.sort();
    return FormulaMeasurement(
      backend: backend.id,
      coldLoad: cold.elapsed,
      edits: edits,
      longestPause: await ticker.stop(),
      checksum: engine.valueOf(CellAddress(workload.depth, 1)),
    );
  } finally {
    ticker.kill();
  }
}

/// Runs the gate: [candidate] against the native control, plus G5 —
/// [differentialGreen], the verdict of the conformance corpus.
Future<FormulaGateReport> runFormulaPromotionGate(
  FormulaEvaluationBackend candidate, {
  required bool differentialGreen,
  FormulaWorkload workload = FormulaWorkload.gate,
}) async {
  final native = await measureFormulaBackend(
    const NativeFormulaBackend(),
    workload: workload,
  );
  final measured = await measureFormulaBackend(candidate, workload: workload);
  String ms(Duration d) => '${(d.inMicroseconds / 1000).toStringAsFixed(2)} ms';
  double ratio(Duration a, Duration b) => b.inMicroseconds == 0
      ? double.infinity
      : a.inMicroseconds / b.inMicroseconds;
  final coldRatio = ratio(measured.coldLoad, native.coldLoad);
  final editRatio = ratio(measured.median, native.median);
  return FormulaGateReport(workload, native, measured, [
    FormulaGateResult(
      'G1',
      measured.coldLoad <= const Duration(milliseconds: 1000),
      'cold load ${ms(measured.coldLoad)} (bound 1000 ms)',
    ),
    FormulaGateResult(
      'G2',
      measured.median <= const Duration(milliseconds: 16) &&
          measured.p99 <= const Duration(milliseconds: 50),
      'edit median ${ms(measured.median)} (bound 16 ms), p99 '
          '${ms(measured.p99)} (bound 50 ms)',
    ),
    FormulaGateResult(
      'G3',
      measured.longestPause <= const Duration(milliseconds: 100),
      'longest stop-the-world gap ${ms(measured.longestPause)} (bound 100 ms)',
    ),
    FormulaGateResult(
      'G4',
      coldRatio <= 2 && editRatio <= 2,
      'cold load ${coldRatio.toStringAsFixed(1)}× native, edit median '
          '${editRatio.toStringAsFixed(1)}× native (bound 2×)',
    ),
    FormulaGateResult(
      'G5',
      differentialGreen && measured.checksum == native.checksum,
      differentialGreen
          ? 'differential suite green; workload checksums '
                '${measured.checksum == native.checksum ? 'agree' : 'DISAGREE'}'
          : 'differential suite not green',
    ),
  ]);
}

/// A ticker isolate in the workload's isolate group, recording the longest
/// gap between its wake-ups.
class _PauseTicker {
  _PauseTicker._(this._isolate, this._control, this._result);

  final Isolate _isolate;
  final SendPort _control;
  final ReceivePort _result;

  static Future<_PauseTicker> start() async {
    final handshake = ReceivePort();
    final result = ReceivePort();
    final isolate = await Isolate.spawn(_tick, (
      handshake.sendPort,
      result.sendPort,
    ));
    final control = await handshake.first as SendPort;
    return _PauseTicker._(isolate, control, result);
  }

  Future<Duration> stop() async {
    _control.send(null);
    final micros = await _result.first as int;
    return Duration(microseconds: micros);
  }

  void kill() {
    _result.close();
    _isolate.kill(priority: Isolate.immediate);
  }

  /// Sleeps a millisecond at a time and keeps the longest overshoot. `sleep`
  /// blocks this isolate's thread only, so the workload runs beside it.
  static Future<void> _tick((SendPort, SendPort) ports) async {
    final (handshake, result) = ports;
    final control = ReceivePort();
    handshake.send(control.sendPort);
    var stopped = false;
    control.listen((_) => stopped = true);
    final clock = Stopwatch()..start();
    var longest = 0;
    var last = clock.elapsedMicroseconds;
    while (!stopped) {
      // Batches of ticks, then a yield so the stop message can be delivered.
      for (var i = 0; i < 50; i++) {
        sleep(const Duration(milliseconds: 1));
        final now = clock.elapsedMicroseconds;
        final gap = now - last - 1000;
        if (gap > longest) longest = gap;
        last = now;
      }
      await Future<void>.delayed(Duration.zero);
      last = clock.elapsedMicroseconds;
    }
    result.send(longest);
    control.close();
  }
}

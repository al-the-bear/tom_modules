/// What a host of a formula backend tests with: the conformance corpus every
/// backend must agree with the native one on, and the promotion-gate
/// benchmark.
///
/// Not part of the default entry point: the benchmark measures pauses with an
/// isolate and `dart:io`.
library;

export 'src/testing/benchmark.dart';
export 'src/testing/corpus.dart';
export 'src/testing/corpus_data.dart';

// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// What LibreOffice detection answers: [LibreOfficeInstallation]. Pure Dart;
/// the detector itself (`dart:io`) is `TomLibreOfficeDetector` in `io.dart`.
library;

import 'package:flutter/foundation.dart';

/// The minimum LibreOffice version (DPLD-1): the version installed on mbp,
/// the one the prototype is tested against.
const kLibreOfficeMinimumVersion = '26.8.3.1';

/// LibreOffice's download page, shown with `missing` and `tooOld`.
const kLibreOfficeDownloadUrl = 'https://www.libreoffice.org/download/';

/// The state of a LibreOffice copy, or of the search for one.
enum LibreOfficeState {
  /// Usable, at or above the minimum version.
  found,

  /// No copy anywhere (or none at the path the user set).
  missing,

  /// A copy below the minimum version.
  tooOld,

  /// The bundle is incomplete, its library is missing or of another
  /// architecture, its signature fails, or the version cross-check fails.
  damaged,

  /// The bundle carries `com.apple.quarantine` and has not been opened yet,
  /// so Gatekeeper would block the helper loading its libraries.
  quarantined,
}

/// One answer of detection: a copy (or none) and its state.
@immutable
final class LibreOfficeInstallation {
  /// An answer from its parts.
  const LibreOfficeInstallation({
    required this.state,
    this.bundlePath,
    this.version,
    this.bundleId,
    this.reason,
    this.source = '',
  });

  /// The state.
  final LibreOfficeState state;

  /// The application bundle (`…/LibreOffice.app`), or `null` when none.
  final String? bundlePath;

  /// `CFBundleShortVersionString`, e.g. `26.8.3.1`.
  final String? version;

  /// `CFBundleIdentifier`, e.g. `org.libreoffice.script`.
  final String? bundleId;

  /// Why the copy is not usable: the output of the failing check.
  final String? reason;

  /// Where it was found: `setting`, `applications`, `home`, `spotlight`,
  /// `path`, `homebrew`, `macports`.
  final String source;

  /// Whether the helper can be started with it.
  bool get isUsable => state == LibreOfficeState.found;

  /// The program folder handed to the helper (`lok_init_2`'s install path):
  /// `Contents/Frameworks`, holding `libmergedlo.dylib`.
  String? get programPath =>
      bundlePath == null ? null : '$bundlePath/Contents/Frameworks';

  /// `Contents/MacOS/soffice`.
  String? get sofficePath =>
      bundlePath == null ? null : '$bundlePath/Contents/MacOS/soffice';

  @override
  bool operator ==(Object other) =>
      other is LibreOfficeInstallation &&
      other.state == state &&
      other.bundlePath == bundlePath &&
      other.version == version &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(state, bundlePath, version, reason);

  @override
  String toString() =>
      'LibreOfficeInstallation(${state.name}'
      '${bundlePath == null ? '' : ', $bundlePath'}'
      '${version == null ? '' : ', $version'}'
      '${reason == null ? '' : ', $reason'})';
}

/// Compares dotted version strings numerically (`26.8.10` > `26.8.9`); a
/// missing part counts as 0, a non-numeric part as 0.
int compareLibreOfficeVersions(String a, String b) {
  final pa = a.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  final pb = b.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  for (var i = 0; i < pa.length || i < pb.length; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

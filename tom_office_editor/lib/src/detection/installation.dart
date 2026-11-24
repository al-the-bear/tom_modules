// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// What LibreOffice detection answers: [LibreOfficeInstallation]. Pure Dart;
/// the detector itself (`dart:io`) is `TomLibreOfficeDetector` in `io.dart`.
library;

import 'package:flutter/foundation.dart';

/// The minimum LibreOffice version on macOS and Windows (DPLD-1): the
/// version installed on mbp, the one the prototype is tested against. Linux's
/// is `kLibreOfficeMinimumVersionLinux` (DPLD-4); each platform's is in
/// `TomLibreOfficeTool.standard`.
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
    this.programFolder,
    this.sofficeExecutable,
    this.minimumVersion,
  });

  /// The state.
  final LibreOfficeState state;

  /// The application bundle (`…/LibreOffice.app`; on Linux and Windows the
  /// installation folder above `program`), or `null` when none.
  final String? bundlePath;

  /// `CFBundleShortVersionString`, e.g. `26.8.3.1`.
  final String? version;

  /// `CFBundleIdentifier`, e.g. `org.libreoffice.script`.
  final String? bundleId;

  /// Why the copy is not usable: the output of the failing check.
  final String? reason;

  /// Where it was found: `setting`, `applications`, `home`, `spotlight`,
  /// `path`, `homebrew`, `macports`; on Linux `tdf`, `distribution`; on
  /// Windows `programFiles`.
  final String source;

  /// The program folder, when it is not the macOS bundle's
  /// `Contents/Frameworks` (Linux: `/opt/libreoffice26.8/program`).
  final String? programFolder;

  /// `soffice`, when it is not the macOS bundle's `Contents/MacOS/soffice`.
  final String? sofficeExecutable;

  /// The platform's minimum version detection compared with (set on
  /// `tooOld`); `null` means [kLibreOfficeMinimumVersion].
  final String? minimumVersion;

  /// Whether the user's path setting names something that is no usable
  /// LibreOffice (nothing there, or not a LibreOffice): the install help's
  /// *unusable path*.
  bool get isUnusableSetting =>
      source == 'setting' &&
      (state == LibreOfficeState.missing || state == LibreOfficeState.damaged);

  /// Whether the helper can be started with it.
  bool get isUsable => state == LibreOfficeState.found;

  /// The program folder handed to the helper (`lok_init_2`'s install path):
  /// `Contents/Frameworks`, holding `libmergedlo.dylib`.
  /// On Linux and Windows [programFolder].
  String? get programPath =>
      programFolder ??
      (bundlePath == null ? null : '$bundlePath/Contents/Frameworks');

  /// `Contents/MacOS/soffice`; on Linux and Windows [sofficeExecutable].
  String? get sofficePath =>
      sofficeExecutable ??
      (bundlePath == null ? null : '$bundlePath/Contents/MacOS/soffice');

  @override
  bool operator ==(Object other) =>
      other is LibreOfficeInstallation &&
      other.state == state &&
      other.bundlePath == bundlePath &&
      other.version == version &&
      other.reason == reason &&
      other.programFolder == programFolder;

  @override
  int get hashCode =>
      Object.hash(state, bundlePath, version, reason, programFolder);

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

// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:io';

import 'package:path/path.dart' as p;

import '../detection/libreoffice_tool.dart';

/// Which of [routes] can run here, by route id: a route whose package
/// manager's executables are all on [searchPath] (default `PATH`), or which
/// needs none. On Windows an executable is also looked for with `.exe`,
/// `.cmd` and `.bat`. What `TomLibreOfficeInstallHelp.routeAvailability`
/// takes. It starts nothing.
Map<String, bool> installRouteAvailability(
  List<TomInstallRoute> routes, {
  String? searchPath,
  TomToolPlatform? platform,
}) {
  final windows =
      (platform ?? TomToolPlatform.fromName(Platform.operatingSystem)) ==
      TomToolPlatform.windows;
  final dirs = (searchPath ?? Platform.environment['PATH'] ?? '')
      .split(windows ? ';' : ':')
      .where((d) => d.isNotEmpty)
      .toList();
  bool onPath(String name) {
    final names = windows
        ? [name, '$name.exe', '$name.cmd', '$name.bat']
        : [name];
    for (final dir in dirs) {
      for (final n in names) {
        if (File(p.join(dir, n)).existsSync()) return true;
      }
    }
    return false;
  }

  return {
    for (final route in routes)
      route.id: route.packageManager?.executables.every(onPath) ?? true,
  };
}

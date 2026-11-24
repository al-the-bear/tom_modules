// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The help a user gets when LibreOffice is missing, too old or the path
/// set is unusable (`part-libreoffice-detection`, *Installing for the
/// user*, DPLD-3, DPLD-4): what is missing and why, the platform's install
/// routes, the confirmation, the run's output and end, the download page,
/// *Check again*. Any host shows it; the host runs the commands.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../detection/install_run.dart';
import '../detection/installation.dart';
import '../detection/libreoffice_tool.dart';
import '../office_editor_trail.dart';
import 'panels.dart';

/// What the install help says is wrong.
enum TomLibreOfficeProblem {
  /// No copy anywhere.
  notFound,

  /// A copy below the platform's minimum.
  tooOld,

  /// The user's path setting names nothing usable (nothing there, or not a
  /// LibreOffice).
  unusablePath,

  /// A found copy that cannot be used (incomplete, wrong architecture,
  /// failed cross-check).
  damaged,

  /// macOS has not confirmed the copy yet.
  quarantined,

  /// Nothing: LibreOffice is ready.
  none;

  /// The problem of [installation].
  static TomLibreOfficeProblem of(LibreOfficeInstallation installation) {
    if (installation.isUnusableSetting) return unusablePath;
    return switch (installation.state) {
      LibreOfficeState.found => none,
      LibreOfficeState.missing => notFound,
      LibreOfficeState.tooOld => tooOld,
      LibreOfficeState.damaged => damaged,
      LibreOfficeState.quarantined => quarantined,
    };
  }

  /// Whether installing LibreOffice is the answer.
  bool get offersInstall =>
      this == notFound ||
      this == tooOld ||
      this == unusablePath ||
      this == damaged;
}

/// The install help for one detection result.
class TomLibreOfficeInstallHelp extends StatefulWidget {
  /// The help for [installation] on [platform] (default: the platform this
  /// runs on, macOS where there is none). Each callback adds its button.
  const TomLibreOfficeInstallHelp({
    super.key,
    required this.installation,
    this.platform,
    this.tool = TomLibreOfficeTool.standard,
    this.onInstall,
    this.onOpenDownloadPage,
    this.onCheckAgain,
    this.routeAvailability,
  });

  /// Detection's answer.
  final LibreOfficeInstallation installation;

  /// The platform whose routes are shown.
  final TomToolPlatform? platform;

  /// The descriptor.
  final TomLibreOfficeTool tool;

  /// Runs a route after the user confirmed it; without it the routes are
  /// shown with their commands only.
  final TomLibreOfficeInstaller? onInstall;

  /// Opens the download page (the URL is given).
  final ValueChanged<String>? onOpenDownloadPage;

  /// *Check again*: detect again.
  final VoidCallback? onCheckAgain;

  /// Which routes can run here, by route id (`installRouteAvailability` in
  /// `io.dart`); a route marked `false` is shown with its missing package
  /// manager and cannot be run. Unlisted routes count as available.
  final Map<String, bool>? routeAvailability;

  @override
  State<TomLibreOfficeInstallHelp> createState() =>
      _TomLibreOfficeInstallHelpState();
}

class _TomLibreOfficeInstallHelpState extends State<TomLibreOfficeInstallHelp> {
  TomInstallRoute? _running;
  TomInstallRoute? _ranRoute;
  TomLibreOfficeInstallRun? _run;
  final _output = StringBuffer();
  TomLibreOfficeInstallResult? _result;
  StreamSubscription<String>? _subscription;

  TomToolPlatform get _platform =>
      widget.platform ?? TomToolPlatform.current ?? TomToolPlatform.macos;

  @override
  void didUpdateWidget(TomLibreOfficeInstallHelp old) {
    super.didUpdateWidget(old);
    if (old.installation != widget.installation && _running == null) {
      // A new detection: the last run's end is no longer news.
      _ranRoute = null;
      _result = null;
      _output.clear();
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  Future<void> _confirmAndRun(TomInstallRoute route) async {
    officeTrail('install-help confirm ${route.id}');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _ConfirmDialog(route: route),
    );
    if (!mounted) return;
    if (confirmed != true) {
      officeTrail('install-help cancelled ${route.id}');
      return;
    }
    final install = widget.onInstall;
    if (install == null) return;
    officeTrail('install-help run ${route.id}');
    final TomLibreOfficeInstallRun run;
    try {
      run = install(route);
    } catch (e, st) {
      officeReport(e, st, 'install-help: onInstall(${route.id})');
      setState(() {
        _ranRoute = route;
        _output.clear();
        _result = TomLibreOfficeInstallResult(-1, message: '$e');
      });
      return;
    }
    setState(() {
      _running = route;
      _ranRoute = route;
      _run = run;
      _output.clear();
      _result = null;
    });
    _subscription = run.output.listen(
      (text) {
        if (mounted) setState(() => _output.write(text));
      },
      onError: (Object e) {
        if (mounted) setState(() => _output.writeln('$e'));
      },
    );
    TomLibreOfficeInstallResult result;
    try {
      result = await run.result;
    } catch (e) {
      result = TomLibreOfficeInstallResult(-1, message: '$e');
    }
    officeTrail('install-help end ${route.id}: exit ${result.exitCode}');
    if (!mounted) return;
    setState(() {
      _running = null;
      _run = null;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final installation = widget.installation;
    final problem = TomLibreOfficeProblem.of(installation);
    final spec = widget.tool.spec(_platform);
    final minimum = installation.minimumVersion ?? spec.minimumVersion;
    final (title, why) = _texts(problem, installation, minimum);
    final routes = problem.offersInstall
        ? spec.routes
        : const <TomInstallRoute>[];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.description_outlined, size: 40),
              const SizedBox(height: 12),
              Text(
                title,
                key: const ValueKey('office-install-title'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              if (why.isNotEmpty) ...[
                const SizedBox(height: 8),
                SelectableText(
                  why,
                  key: const ValueKey('office-install-why'),
                  textAlign: TextAlign.center,
                ),
              ],
              if (routes.isNotEmpty && spec.warnings.isNotEmpty) ...[
                const SizedBox(height: 16),
                _Warnings(warnings: spec.warnings),
              ],
              if (routes.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Install LibreOffice on ${_platform.label}',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                for (final route in routes)
                  _RouteCard(
                    route: route,
                    tool: widget.tool,
                    minimum: spec.minimumVersion,
                    available: widget.routeAvailability?[route.id] ?? true,
                    onInstall:
                        widget.onInstall == null ||
                            _running != null ||
                            !route.runnable
                        ? null
                        : () => _confirmAndRun(route),
                    onOpenDownloadPage: widget.onOpenDownloadPage == null
                        ? null
                        : () => widget.onOpenDownloadPage!(
                            route.url ?? widget.tool.downloadPage,
                          ),
                  ),
                const SizedBox(height: 4),
                Text(
                  widget.tool.licenceNotice,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (_ranRoute != null) ...[
                const SizedBox(height: 16),
                _RunView(
                  route: _ranRoute!,
                  output: _output.toString(),
                  result: _result,
                  onStop: _run?.cancel,
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (widget.onCheckAgain != null)
                    FilledButton(
                      key: const ValueKey('office-install-check-again'),
                      onPressed: _running == null
                          ? () {
                              officeTrail('install-help check again');
                              widget.onCheckAgain!();
                            }
                          : null,
                      child: const Text('Check again'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  (String, String) _texts(
    TomLibreOfficeProblem problem,
    LibreOfficeInstallation installation,
    String minimum,
  ) {
    final platform = _platform.label;
    final needs =
        'The office editor shows and edits documents with an installed '
        'LibreOffice $minimum or newer.';
    return switch (problem) {
      TomLibreOfficeProblem.notFound => (
        'LibreOffice is not installed.',
        '$needs None was found in the usual places on $platform.',
      ),
      TomLibreOfficeProblem.tooOld => (
        'LibreOffice ${installation.version ?? '?'} is older than '
            '$minimum.',
        '$needs Older versions open some documents wrongly or not at all. '
            'Install a newer one.',
      ),
      TomLibreOfficeProblem.unusablePath => (
        'The LibreOffice path you set cannot be used.',
        '${installation.bundlePath ?? ''}: '
            '${installation.reason ?? 'it is not a LibreOffice.'} '
            'Choose another path in the settings, or install LibreOffice.',
      ),
      TomLibreOfficeProblem.damaged => (
        'LibreOffice at ${installation.bundlePath ?? '?'} cannot be used.',
        '${installation.reason ?? ''} Installing it again may help.'.trim(),
      ),
      TomLibreOfficeProblem.quarantined => (
        libreOfficeStateMessage(installation),
        '',
      ),
      TomLibreOfficeProblem.none => (
        'LibreOffice ${installation.version ?? ''} is ready.',
        '',
      ),
    };
  }
}

class _Warnings extends StatelessWidget {
  const _Warnings({required this.warnings});

  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('office-install-warnings'),
      color: scheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final w in warnings)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_outlined,
                      size: 16,
                      color: scheme.onTertiaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        w,
                        style: TextStyle(color: scheme.onTertiaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({
    required this.route,
    required this.tool,
    required this.minimum,
    required this.available,
    required this.onInstall,
    required this.onOpenDownloadPage,
  });

  final TomInstallRoute route;
  final TomLibreOfficeTool tool;
  final String minimum;
  final bool available;
  final VoidCallback? onInstall;
  final VoidCallback? onOpenDownloadPage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace');
    final manager = route.packageManager;
    final download = route.download;
    return Card(
      key: ValueKey('office-install-route-${route.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(route.label, style: theme.textTheme.titleSmall),
                ),
                if (route.versionOffered != null)
                  Text(
                    'LibreOffice ${route.versionOffered}',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
            if (download != null) ...[
              const SizedBox(height: 4),
              SelectableText(download.url(), style: mono),
              Text(
                'Checked against its SHA-256: ${download.hashUrl()}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            for (final line in route.commandLines) ...[
              const SizedBox(height: 4),
              SelectableText(line, style: mono),
            ],
            if (route.runnable) ...[
              const SizedBox(height: 4),
              Text(
                route.elevation.description,
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 4),
            for (final (i, step) in route.steps.indexed)
              Text('${i + 1}. $step'),
            if (!available && manager != null) ...[
              const SizedBox(height: 4),
              Text(
                'Needs ${manager.name}, which was not found on this '
                'computer${manager.homepage == null ? '' : ' (${manager.homepage})'}.',
                key: ValueKey('office-install-unavailable-${route.id}'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: route.runnable
                  ? FilledButton.tonal(
                      key: ValueKey('office-install-run-${route.id}'),
                      onPressed: available ? onInstall : null,
                      child: Text('Install with ${route.label}'),
                    )
                  : OutlinedButton(
                      key: const ValueKey('office-install-download'),
                      onPressed: onOpenDownloadPage,
                      child: const Text('Open the download page'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({required this.route});

  final TomInstallRoute route;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace');
    final download = route.download;
    return AlertDialog(
      key: const ValueKey('office-install-confirm-dialog'),
      title: Text('Install LibreOffice with ${route.label}?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (download != null) ...[
              Text(
                'This downloads ${download.fileName()} from '
                'download.documentfoundation.org, checks its SHA-256 '
                'against ${download.hashUrl()}, unpacks it and runs:',
              ),
            ] else
              const Text('This runs:'),
            const SizedBox(height: 8),
            for (final line in route.commandLines)
              SelectableText(line, style: mono),
            const SizedBox(height: 8),
            Text(
              route.elevation.description,
              key: const ValueKey('office-install-confirm-elevation'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('office-install-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('office-install-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Install'),
        ),
      ],
    );
  }
}

class _RunView extends StatelessWidget {
  const _RunView({
    required this.route,
    required this.output,
    required this.result,
    required this.onStop,
  });

  final TomInstallRoute route;
  final String output;
  final TomLibreOfficeInstallResult? result;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = result;
    final String status;
    if (r == null) {
      status = 'Installing with ${route.label}…';
    } else if (r.ok) {
      status =
          'The install with ${route.label} finished. Choose Check again to '
          'use LibreOffice.';
    } else {
      status =
          'The install with ${route.label} failed (exit ${r.exitCode})'
          '${r.message == null ? '' : ': ${r.message}'}. '
          'Check again, or try another route.';
    }
    return Card(
      key: const ValueKey('office-install-run'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (r == null) ...[
                  const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      r.ok ? Icons.check_circle_outline : Icons.error_outline,
                      size: 16,
                      color: r.ok ? null : theme.colorScheme.error,
                    ),
                  ),
                Expanded(
                  child: Text(
                    status,
                    key: const ValueKey('office-install-status'),
                  ),
                ),
                if (r == null && onStop != null)
                  TextButton(
                    key: const ValueKey('office-install-stop'),
                    onPressed: onStop,
                    child: const Text('Stop'),
                  ),
              ],
            ),
            if (output.isNotEmpty) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: SingleChildScrollView(
                  reverse: true,
                  child: SelectableText(
                    output,
                    key: const ValueKey('office-install-output'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

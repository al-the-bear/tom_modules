import 'package:flutter/material.dart';

import 'validation_badge.dart' show ValidationTheme;
import 'validation_error.dart';

/// Mouse-over tooltip listing validation errors with severity icons and path.
///
/// Designed to appear when hovering over a tree node that has validation
/// errors. Shows all errors at that path with severity icon, message, and
/// the full path breadcrumb.
///
/// ```dart
/// ValidationTooltip(
///   errors: [
///     ValidationError(
///       path: ['prompt', 'id'],
///       message: 'Pattern violation',
///       severity: ValidationSeverity.error,
///     ),
///   ],
///   theme: ValidationTheme(),
/// )
/// ```
class ValidationTooltip extends StatelessWidget {
  /// The validation errors to display.
  final List<ValidationError> errors;

  /// Visual theme.
  final ValidationTheme theme;

  /// Maximum width of the tooltip.
  final double maxWidth;

  const ValidationTooltip({
    super.key,
    required this.errors,
    this.theme = const ValidationTheme(),
    this.maxWidth = 400,
  });

  @override
  Widget build(BuildContext context) {
    if (errors.isEmpty) return const SizedBox.shrink();

    // Group by severity for display ordering: errors first, then warnings, then info
    var sorted = List<ValidationError>.from(errors)
      ..sort((a, b) => a.severity.index.compareTo(b.severity.index));

    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.tooltipBackground,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: _dominantColor,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(60),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < sorted.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            _buildErrorRow(sorted[i]),
          ],
          if (errors.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Path: ${errors.first.pathString}',
              style: theme.pathStyle,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorRow(ValidationError error) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _iconForSeverity(error.severity),
          size: 14,
          color: _colorForSeverity(error.severity),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            error.message,
            style: theme.messageStyle,
          ),
        ),
      ],
    );
  }

  Color get _dominantColor {
    if (errors.any((e) => e.severity == ValidationSeverity.error)) {
      return theme.errorColor;
    }
    if (errors.any((e) => e.severity == ValidationSeverity.warning)) {
      return theme.warningColor;
    }
    return theme.infoColor;
  }

  Color _colorForSeverity(ValidationSeverity severity) {
    switch (severity) {
      case ValidationSeverity.error:
        return theme.errorColor;
      case ValidationSeverity.warning:
        return theme.warningColor;
      case ValidationSeverity.info:
        return theme.infoColor;
    }
  }

  IconData _iconForSeverity(ValidationSeverity severity) {
    switch (severity) {
      case ValidationSeverity.error:
        return Icons.cancel;
      case ValidationSeverity.warning:
        return Icons.warning;
      case ValidationSeverity.info:
        return Icons.info_outline;
    }
  }
}

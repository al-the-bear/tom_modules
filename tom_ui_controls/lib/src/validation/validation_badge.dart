import 'package:flutter/material.dart';

/// Theme for validation display widgets.
class ValidationTheme {
  /// Color for error indicators.
  final Color errorColor;

  /// Color for warning indicators.
  final Color warningColor;

  /// Color for info indicators.
  final Color infoColor;

  /// Background color for tooltips.
  final Color tooltipBackground;

  /// Border color for tooltips.
  final Color tooltipBorder;

  /// Text style for validation messages.
  final TextStyle messageStyle;

  /// Text style for path breadcrumbs.
  final TextStyle pathStyle;

  /// Badge font size.
  final double badgeFontSize;

  const ValidationTheme({
    this.errorColor = const Color(0xFFF44747),
    this.warningColor = const Color(0xFFCCA700),
    this.infoColor = const Color(0xFF808080),
    this.tooltipBackground = const Color(0xFF252526),
    this.tooltipBorder = const Color(0xFF454545),
    this.messageStyle = const TextStyle(fontSize: 12, color: Color(0xFFCCCCCC)),
    this.pathStyle = const TextStyle(
      fontSize: 11,
      color: Color(0xFF808080),
      fontStyle: FontStyle.italic,
    ),
    this.badgeFontSize = 10,
  });
}

/// A compact badge showing error and/or warning count.
///
/// Displays a small colored pill with the count of validation issues.
/// Shows nothing when there are zero errors and zero warnings.
///
/// ```dart
/// ValidationBadge(
///   errorCount: 2,
///   warningCount: 1,
///   theme: ValidationTheme(),
/// )
/// ```
class ValidationBadge extends StatelessWidget {
  /// Number of errors.
  final int errorCount;

  /// Number of warnings.
  final int warningCount;

  /// Visual theme.
  final ValidationTheme theme;

  /// Whether this badge represents propagated (ancestor) errors.
  ///
  /// If true, the badge is rendered with reduced opacity to distinguish
  /// it from direct errors.
  final bool isPropagated;

  const ValidationBadge({
    super.key,
    this.errorCount = 0,
    this.warningCount = 0,
    this.theme = const ValidationTheme(),
    this.isPropagated = false,
  });

  @override
  Widget build(BuildContext context) {
    if (errorCount == 0 && warningCount == 0) {
      return const SizedBox.shrink();
    }

    var children = <Widget>[];

    if (errorCount > 0) {
      children.add(_buildPill(
        count: errorCount,
        color: theme.errorColor,
        icon: Icons.error_outline,
      ));
    }

    if (warningCount > 0) {
      if (children.isNotEmpty) children.add(const SizedBox(width: 4));
      children.add(_buildPill(
        count: warningCount,
        color: theme.warningColor,
        icon: Icons.warning_amber,
      ));
    }

    return Semantics(
      label: [
        if (errorCount > 0) '$errorCount error${errorCount == 1 ? '' : 's'}',
        if (warningCount > 0)
          '$warningCount warning${warningCount == 1 ? '' : 's'}',
      ].join(', '),
      child: Opacity(
        opacity: isPropagated ? 0.5 : 1.0,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    );
  }

  Widget _buildPill({
    required int count,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(80), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: theme.badgeFontSize + 2, color: color),
          const SizedBox(width: 2),
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: theme.badgeFontSize,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

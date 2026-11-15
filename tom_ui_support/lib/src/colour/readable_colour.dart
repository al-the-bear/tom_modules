/// Colours that stay readable on whatever they are painted on.
///
/// A hue often carries meaning — a priority's orange, a due date's teal — and
/// the theme's scheme has no slot for it. Painting the bare Material hue gave
/// orange text at 1.9:1 on its own tinted chip in the light theme and purple at
/// 2.7:1 in the dark one. [tomReadableOn] keeps the hue and moves only its
/// lightness, darker on a light background and lighter on a dark one, until
/// it meets WCAG AA.
library;

import 'package:flutter/material.dart';

/// The WCAG contrast ratio of two opaque colours.
double tomContrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// [colour] with its HSL lightness moved, as little as it takes, until it
/// reaches [ratio] against the opaque [background] — 4.5:1 for text, 3:1 for
/// large text and icons.
Color tomReadableOn(Color colour, Color background, {double ratio = 4.5}) {
  final opaque = colour.withValues(alpha: 1);
  if (tomContrastRatio(opaque, background) >= ratio) return opaque;
  final hsl = HSLColor.fromColor(opaque);
  final darker = background.computeLuminance() > 0.18;
  for (var step = 1; step <= 50; step++) {
    final lightness =
        (hsl.lightness + (darker ? -step : step) * 0.02).clamp(0.0, 1.0);
    final candidate = hsl.withLightness(lightness).toColor();
    if (tomContrastRatio(candidate, background) >= ratio) return candidate;
  }
  return darker ? Colors.black : Colors.white;
}

/// A tinted chip's two colours: [hue] at 12 % over [surface] as an opaque
/// background, and [hue] made readable on it as the foreground.
({Color background, Color foreground, Color border}) tomTintedChip(
  Color hue,
  Color surface,
) {
  final background = Color.alphaBlend(hue.withValues(alpha: 0.12), surface);
  return (
    background: background,
    foreground: tomReadableOn(hue, background),
    border: Color.alphaBlend(hue.withValues(alpha: 0.4), surface),
  );
}

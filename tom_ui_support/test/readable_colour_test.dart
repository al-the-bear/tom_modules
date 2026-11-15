/// wonetestb4 — the readable-colour helpers keep a hue and move its lightness
/// until it reaches WCAG AA on its background.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_ui_support/tom_ui_support.dart';

void main() {
  final light = ColorScheme.fromSeed(seedColor: const Color(0xFF3F51B5));
  final dark = ColorScheme.fromSeed(
    seedColor: const Color(0xFF3F51B5),
    brightness: Brightness.dark,
  );

  test('WONETESTB4-R1: the contrast ratio is WCAG\'s — black on white is 21, '
      'a colour on itself is 1 [1013]', () {
    expect(tomContrastRatio(Colors.black, Colors.white),
        closeTo(21, 1e-9));
    expect(tomContrastRatio(Colors.white, Colors.black),
        closeTo(21, 1e-9));
    expect(tomContrastRatio(Colors.orange, Colors.orange),
        closeTo(1, 1e-9));
  });

  test('WONETESTB4-R2: a colour already readable is returned as it is '
      '[1013]', () {
    expect(tomReadableOn(Colors.black, Colors.white), Colors.black);
  });

  test('WONETESTB4-R3: a light hue on a light surface is darkened to 4.5:1, '
      'a dark one on a dark surface lightened [1013]', () {
    final onLight = tomReadableOn(Colors.orange, light.surface);
    expect(tomContrastRatio(onLight, light.surface),
        greaterThanOrEqualTo(4.5));
    expect(onLight.computeLuminance(),
        lessThan(Colors.orange.computeLuminance()));
    final onDark = tomReadableOn(Colors.indigo, dark.surface);
    expect(tomContrastRatio(onDark, dark.surface),
        greaterThanOrEqualTo(4.5));
    expect(onDark.computeLuminance(),
        greaterThan(Colors.indigo.computeLuminance()));
  });

  test('WONETESTB4-R4: the hue survives — only the lightness moves [1013]',
      () {
    final moved = tomReadableOn(Colors.orange, light.surface);
    expect(HSLColor.fromColor(moved).hue,
        closeTo(HSLColor.fromColor(Colors.orange).hue, 1));
  });

  test('WONETESTB4-R5: the 3:1 rule for icons and large text needs less '
      'change [1013]', () {
    final text = tomReadableOn(Colors.orange, light.surface);
    final icon = tomReadableOn(Colors.orange, light.surface, ratio: 3);
    expect(tomContrastRatio(icon, light.surface),
        greaterThanOrEqualTo(3));
    expect(icon.computeLuminance(), greaterThan(text.computeLuminance()));
  });

  test('WONETESTB4-R6: a tinted chip\'s text is readable on its own '
      'background, for every Material hue, in both themes [1013]', () {
    for (final scheme in [light, dark]) {
      for (final hue in Colors.primaries) {
        final chip = tomTintedChip(hue, scheme.surface);
        expect(tomContrastRatio(chip.foreground, chip.background),
            greaterThanOrEqualTo(4.5),
            reason: '$hue on ${scheme.brightness}');
      }
    }
  });
}

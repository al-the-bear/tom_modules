/// The golden harness's contrast check: every visible text run and icon in a
/// shot is painted readably against the surface behind it.
///
/// A golden says "the same as last time"; a marker says "the content is
/// there". Neither notices a value drawn light grey on white — a section that
/// renders "nothing" because everything in it is near-white. This states the
/// property on what the eye gets.
///
/// **The rule** is WCAG 2.2 AA: 4.5:1 for text, 3:1 for large text (18 pt, or
/// 14 pt bold — 24 and 18.67 logical pixels) and for icons (1.4.11, non-text
/// contrast). **Exempt**, as WCAG exempts them: a disabled control (1.4.3,
/// 1.4.11, "inactive user interface components") — a Material control
/// switched off, an `InkWell` / `InkResponse` with no handler, anything whose
/// semantics say it is not enabled — and text that is not visible: offstage,
/// outside the window, or fully transparent. A run the rule would fail but an
/// exemption skips is reported with its reason ([tomContrastScan]), so a case
/// can show what was skipped and why.
///
/// **How the colours are found.** The text colour is the one the paragraph
/// paints: the span's own style colour, inherited down the span tree. The
/// background is the nearest painted surface above the paragraph in the
/// widget tree — a `ColoredBox`, a `DecoratedBox` with a colour, a `Material`
/// that is not transparent (its own colour or the theme's for its type) —
/// composited onto the next one when it is translucent, as the screen
/// composites it. That is a model of painting, not a pixel read; it is what
/// can tell a reader which widget's colour to change.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tom_ui_support/tom_ui_support.dart';

/// [top] painted over the opaque [bottom].
Color _over(Color top, Color bottom) {
  final a = top.a;
  if (a >= 1) return top;
  return Color.from(
    alpha: 1,
    red: top.r * a + bottom.r * (1 - a),
    green: top.g * a + bottom.g * (1 - a),
    blue: top.b * a + bottom.b * (1 - a),
  );
}

/// One run that failed the rule.
class TomContrastFinding {
  TomContrastFinding(this.text, this.ratio, this.required, this.fg, this.bg,
      this.where);
  final String text;
  final double ratio;
  final double required;
  final Color fg;
  final Color bg;
  final String where;

  @override
  String toString() => '"$text" ${ratio.toStringAsFixed(2)}:1 '
      '(needs ${required.toStringAsFixed(1)}:1) — '
      '${_hex(fg)} on ${_hex(bg)} — in $where';

  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
}

/// The background colour painted behind [element], or null when none is
/// found below the root.
Color? _background(Element element) {
  final layers = <Color>[];
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    Color? colour;
    if (widget is ColoredBox) {
      colour = widget.color;
    } else if (widget is DecoratedBox) {
      final d = widget.decoration;
      if (d is BoxDecoration && widget.position == DecorationPosition.background) {
        colour = d.color;
      } else if (d is ShapeDecoration) {
        colour = d.color;
      }
    } else if (widget is Material && widget.type != MaterialType.transparency) {
      final theme = Theme.of(ancestor);
      colour = widget.color ??
          switch (widget.type) {
            MaterialType.card => theme.cardColor,
            _ => theme.canvasColor,
          };
    }
    if (colour != null && colour.a > 0) {
      layers.add(colour);
      if (colour.a >= 1) return false;
    }
    return true;
  });
  if (layers.isEmpty || layers.last.a < 1) return null;
  var result = layers.last;
  for (final layer in layers.reversed.skip(1)) {
    result = _over(layer, result);
  }
  return result;
}

/// Why a run the rule would fail is not held to it.
class TomContrastExemption {
  TomContrastExemption(this.finding, this.reason);

  /// What the rule would have reported.
  final TomContrastFinding finding;

  /// Why it is exempt ([tomContrastDisabled], [tomContrastHidden]).
  final String reason;

  @override
  String toString() => '$finding — exempt: $reason';
}

/// The reason a disabled control's runs are exempt.
const tomContrastDisabled =
    'a disabled control (WCAG 1.4.3 and 1.4.11 exempt inactive components)';

/// The reason a run that is not painted is exempt.
const tomContrastHidden = 'not visible (offstage, hidden or transparent)';

/// Whether [w] is a tap target with no handler: an ink response nothing can
/// press, which is how a custom toolbar draws a disabled button.
bool _inertInk(Widget w) =>
    w is InkResponse &&
    w.onTap == null &&
    w.onTapDown == null &&
    w.onDoubleTap == null &&
    w.onLongPress == null &&
    w.onSecondaryTap == null &&
    w.onHover == null;

/// Why [element] is exempt — it sits in a control that is disabled, or is not
/// painted — or null when it is held to the rule.
String? _exemption(Element element) {
  String? reason;
  element.visitAncestorElements((ancestor) {
    final w = ancestor.widget;
    if ((w is Offstage && w.offstage) ||
        (w is Opacity && w.opacity == 0) ||
        (w is Visibility && !w.visible)) {
      reason = tomContrastHidden;
    } else if ((w is ButtonStyleButton && !w.enabled) ||
        (w is IconButton && w.onPressed == null) ||
        (w is ListTile && !w.enabled) ||
        (w is PopupMenuItem && !w.enabled) ||
        (w is MenuItemButton && w.onPressed == null) ||
        (w is Semantics && w.properties.enabled == false) ||
        (w is TextField && w.enabled == false) ||
        (w is FilterChip && w.onSelected == null) ||
        (w is ChoiceChip && w.onSelected == null) ||
        (w is ActionChip && w.onPressed == null) ||
        (w is Checkbox && w.onChanged == null) ||
        _inertInk(w)) {
      reason = tomContrastDisabled;
    }
    return reason == null;
  });
  return reason;
}

/// What the contrast check finds under [within]: the runs that fail the rule
/// ([findings]) and the runs it would fail that an exemption skips
/// ([exempted]), each with its reason.
({List<TomContrastFinding> findings, List<TomContrastExemption> exempted})
tomContrastScan(WidgetTester tester, Finder within) {
  final findings = <TomContrastFinding>[];
  final exempted = <TomContrastExemption>[];
  final view = tester.view.physicalSize / tester.view.devicePixelRatio;
  final screen = Offset.zero & view;
  final paragraphs = find.descendant(
    of: within,
    matching: find.byWidgetPredicate((w) => w is RichText),
  );
  for (final element in paragraphs.evaluate()) {
    final render = element.renderObject;
    if (render is! RenderParagraph || !render.attached || !render.hasSize) {
      continue;
    }
    if (render.size.isEmpty) continue;
    final rect = render.localToGlobal(Offset.zero) & render.size;
    if (!rect.overlaps(screen)) continue;
    final exemption = _exemption(element);
    final bg = _background(element);
    if (bg == null) continue;
    var isIcon = false;
    element.visitAncestorElements((a) {
      if (a.widget is Icon) isIcon = true;
      return !isIcon && a.widget is! RichText;
    });
    void visit(InlineSpan span, TextStyle inherited) {
      final style = inherited.merge(span.style);
      if (span is TextSpan) {
        final text = span.text ?? '';
        final colour = style.foreground?.color ?? style.color;
        if (text.trim().isNotEmpty && colour != null && colour.a > 0) {
          final fg = _over(colour, bg);
          final size = style.fontSize ?? 14;
          final bold = (style.fontWeight?.value ?? 400) >= 700;
          final large = size >= 24 || (bold && size >= 18.66);
          final required = isIcon || large ? 3.0 : 4.5;
          final ratio = tomContrastRatio(fg, bg);
          if (ratio + 1e-6 < required) {
            final finding = TomContrastFinding(
              isIcon ? 'icon U+${text.runes.first.toRadixString(16)}' : text,
              ratio,
              required,
              fg,
              bg,
              _where(element),
            );
            if (exemption == null) {
              findings.add(finding);
            } else {
              exempted.add(TomContrastExemption(finding, exemption));
            }
          }
        }
        for (final child in span.children ?? const <InlineSpan>[]) {
          visit(child, style);
        }
      }
    }

    visit(render.text, const TextStyle());
  }
  return (findings: findings, exempted: exempted);
}

/// Every visible run under [within] that fails the rule.
List<TomContrastFinding> findTomLowContrast(
  WidgetTester tester,
  Finder within,
) => tomContrastScan(tester, within).findings;

/// A short path naming the nearest keyed widgets above [element].
String _where(Element element) {
  final names = <String>[];
  element.visitAncestorElements((a) {
    final key = a.widget.key;
    if (key is ValueKey<String>) names.add(key.value);
    return names.length < 3;
  });
  return names.isEmpty ? '(no keyed ancestor)' : names.join(' < ');
}

/// Fails the test when any visible run under [within] is below WCAG AA.
void expectTomReadable(WidgetTester tester, Finder within, {String? shot}) {
  final findings = findTomLowContrast(tester, within);
  expect(findings, isEmpty,
      reason: 'low contrast${shot == null ? '' : ' in $shot'}:\n'
          '${findings.map((f) => '  $f').join('\n')}');
}

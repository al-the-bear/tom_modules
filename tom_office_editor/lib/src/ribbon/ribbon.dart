// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller.dart';
import '../office_editor_trail.dart';
import 'ribbon_model.dart';

/// The tabbed ribbon (`part-office-editor`, *The ribbon*): the tabs of the
/// document type, each control a UNO command whose state follows
/// `STATE_CHANGED`, the dropdowns filled from `getCommandValues`, the colour
/// split buttons with the colour picker. Tab and the arrow keys move between
/// its controls.
class TomOfficeRibbon extends StatefulWidget {
  /// The ribbon of [controller]'s document. [onLocal] runs the controls the
  /// editor handles itself (clipboard, zoom).
  const TomOfficeRibbon({
    super.key,
    required this.controller,
    required this.onLocal,
  });

  /// The document.
  final TomOfficeEditorController controller;

  /// A local control was used.
  final ValueChanged<RibbonLocalAction> onLocal;

  @override
  State<TomOfficeRibbon> createState() => _TomOfficeRibbonState();
}

class _TomOfficeRibbonState extends State<TomOfficeRibbon> {
  int _tab = 0;

  TomOfficeEditorController get _c => widget.controller;

  @override
  Widget build(BuildContext context) {
    final tabs = officeRibbonTabs(_c.docType);
    if (_tab >= tabs.length) _tab = 0;
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.arrowLeft): DirectionalFocusIntent(
            TraversalDirection.left,
          ),
          SingleActivator(LogicalKeyboardKey.arrowRight):
              DirectionalFocusIntent(TraversalDirection.right),
          SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(
            TraversalDirection.up,
          ),
          SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(
            TraversalDirection.down,
          ),
        },
        child: FocusTraversalGroup(
          policy: ReadingOrderTraversalPolicy(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 30,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final (i, tab) in tabs.indexed)
                      TextButton(
                        key: ValueKey('ribbon-tab-${tab.label}'),
                        style: TextButton.styleFrom(
                          foregroundColor: i == _tab
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                          textStyle: TextStyle(
                            fontWeight: i == _tab
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                        onPressed: () => setState(() => _tab = i),
                        child: Text(tab.label),
                      ),
                  ],
                ),
              ),
              SizedBox(
                height: 64,
                // Every control is built (not a lazy list), so focus can
                // move to one scrolled out of view.
                child: SingleChildScrollView(
                  key: const ValueKey('ribbon-groups'),
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      for (final group in tabs[_tab].groups)
                        _Group(
                          group: group,
                          controller: _c,
                          onLocal: widget.onLocal,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.group,
    required this.controller,
    required this.onLocal,
  });

  final RibbonGroup group;
  final TomOfficeEditorController controller;
  final ValueChanged<RibbonLocalAction> onLocal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [for (final control in group.controls) _control(control)],
          ),
          Text(group.label, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }

  Widget _control(RibbonControl control) => switch (control) {
    RibbonCommand() => _CommandButton(control: control, controller: controller),
    RibbonChoice() => _ChoiceButton(control: control, controller: controller),
    RibbonColour() => _ColourButton(control: control, controller: controller),
    RibbonLocal() => _LocalButton(
      control: control,
      controller: controller,
      onLocal: onLocal,
    ),
  };
}

bool _usable(TomOfficeEditorController c, {required bool edits}) =>
    c.state == TomOfficeEditorState.open && (!edits || c.acceptsEdits);

class _CommandButton extends StatelessWidget {
  const _CommandButton({required this.control, required this.controller});

  final RibbonCommand control;
  final TomOfficeEditorController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final enabled =
        _usable(c, edits: control.edits) && c.isEnabled(control.command);
    return IconButton(
      key: ValueKey('ribbon-${control.id}'),
      tooltip: control.label,
      visualDensity: VisualDensity.compact,
      isSelected: control.toggle ? c.isChecked(control.command) : null,
      style: control.toggle
          ? IconButton.styleFrom(
              backgroundColor: c.isChecked(control.command)
                  ? Theme.of(context).colorScheme.secondaryContainer
                  : null,
            )
          : null,
      onPressed: enabled
          ? () {
              officeTrail('ribbon ${control.id}');
              c.uno(control.command, control.args);
            }
          : null,
      icon: Icon(control.icon, size: 20),
    );
  }
}

class _LocalButton extends StatelessWidget {
  const _LocalButton({
    required this.control,
    required this.controller,
    required this.onLocal,
  });

  final RibbonLocal control;
  final TomOfficeEditorController controller;
  final ValueChanged<RibbonLocalAction> onLocal;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final edits = switch (control.action) {
      RibbonLocalAction.cut ||
      RibbonLocalAction.paste ||
      RibbonLocalAction.insertImage => true,
      _ => false,
    };
    return IconButton(
      key: ValueKey('ribbon-${control.id}'),
      tooltip: control.label,
      visualDensity: VisualDensity.compact,
      onPressed: _usable(c, edits: edits)
          ? () {
              officeTrail('ribbon ${control.id}');
              if (control.action == RibbonLocalAction.insertImage) {
                unawaited(c.insertImage());
              } else {
                onLocal(control.action);
              }
            }
          : null,
      icon: Icon(control.icon, size: 20),
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({required this.control, required this.controller});

  final RibbonChoice control;
  final TomOfficeEditorController controller;

  /// The entries, as (value, label).
  Future<List<(String, String)>> _entries() async {
    final c = controller;
    switch (control.source) {
      case RibbonChoiceSource.fixed:
        return control.entries;
      case RibbonChoiceSource.fonts:
        final fonts = await c.fonts();
        return [for (final f in fonts.keys) (f, f)];
      case RibbonChoiceSource.sizes:
        final fonts = await c.fonts();
        final font = c.stateOf('.uno:CharFontName');
        final sizes =
            fonts[font] ?? (fonts.isEmpty ? _defaultSizes : fonts.values.first);
        return [for (final s in sizes) (s, s)];
      case RibbonChoiceSource.paragraphStyles:
        final styles = await c.styles();
        final list =
            styles['ParagraphStyles'] ?? styles['graphics'] ?? const [];
        return [for (final s in list) (s, s)];
    }
  }

  static const _defaultSizes = [
    '8', '9', '10', '11', '12', '14', '16', '18', '20', '24', '28', '36', //
    '48', '72',
  ];

  String _current() {
    final value = control.command.isEmpty
        ? null
        : controller.stateOf(control.command);
    if (value == null || value.isEmpty) return control.label;
    for (final (v, label) in control.entries) {
      if (v == value) return label;
    }
    return value;
  }

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final entries = await _entries();
    if (!context.mounted || entries.isEmpty) return;
    final at = box.localToGlobal(Offset(0, box.size.height), ancestor: overlay);
    final chosen = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        at & Size(box.size.width, 1),
        Offset.zero & overlay.size,
      ),
      constraints: const BoxConstraints(maxHeight: 420, minWidth: 140),
      items: [
        for (final (value, label) in entries)
          PopupMenuItem<String>(
            key: ValueKey('ribbon-${control.id}-$value'),
            value: value,
            height: 30,
            child: Text(label),
          ),
      ],
    );
    if (chosen == null) return;
    officeTrail('ribbon ${control.id}');
    if (control.command.isEmpty) {
      // The entry is the command itself (line spacing).
      controller.uno(chosen);
    } else {
      controller.uno(control.command, control.args(chosen));
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled =
        _usable(controller, edits: true) &&
        (control.command.isEmpty || controller.isEnabled(control.command));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: SizedBox(
        width: control.width,
        height: 30,
        child: Builder(
          builder: (context) => OutlinedButton(
            key: ValueKey('ribbon-${control.id}'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: enabled ? () => unawaited(_open(context)) : null,
            child: Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message: control.label,
                    child: Text(
                      _current(),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const Icon(Icons.arrow_drop_down, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ColourButton extends StatelessWidget {
  const _ColourButton({required this.control, required this.controller});

  final RibbonColour control;
  final TomOfficeEditorController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final enabled = _usable(c, edits: true);
    final colour = c.lastColour(control.command, control.initial);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: ValueKey('ribbon-${control.id}'),
          tooltip: control.label,
          visualDensity: VisualDensity.compact,
          onPressed: enabled
              ? () => c.applyColour(control.command, control.argument, colour)
              : null,
          icon: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(control.icon, size: 18),
              Container(
                width: 18,
                height: 4,
                color: colour < 0 ? Colors.black : Color(0xFF000000 | colour),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 18,
          child: IconButton(
            key: ValueKey('ribbon-${control.id}-menu'),
            tooltip: '${control.label}: more colours',
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            onPressed: enabled ? () => unawaited(_pick(context)) : null,
            icon: const Icon(Icons.arrow_drop_down, size: 16),
          ),
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context) async {
    final choice = await showDialog<_ColourChoice>(
      context: context,
      builder: (context) => TomOfficeColourPicker(
        title: control.label,
        recent: controller.recentColours,
      ),
    );
    if (choice == null) return;
    switch (choice) {
      case _Colour(:final rgb):
        controller.applyColour(control.command, control.argument, rgb);
      case _Custom():
        // LibreOffice's colour dialog has no command of its own: the
        // properties dialog's page holds *Pick…*, which opens it.
        officeTrail('ribbon ${control.id}: custom colour');
        controller.uno(control.customDialog);
    }
  }
}

sealed class _ColourChoice {
  const _ColourChoice();
}

final class _Colour extends _ColourChoice {
  const _Colour(this.rgb);
  final int rgb;
}

final class _Custom extends _ColourChoice {
  const _Custom();
}

/// The colour picker: LibreOffice's palette, the recent colours,
/// *Automatic* and *Custom colour…*.
class TomOfficeColourPicker extends StatelessWidget {
  /// A picker titled [title] with the [recent] colours.
  const TomOfficeColourPicker({
    super.key,
    required this.title,
    required this.recent,
  });

  /// What it picks for.
  final String title;

  /// The recent colours, newest first.
  final List<int> recent;

  Widget _swatch(BuildContext context, int rgb, {String prefix = 'colour'}) {
    final hex = rgb.toRadixString(16).padLeft(6, '0').toUpperCase();
    return Padding(
      padding: const EdgeInsets.all(1.5),
      child: Tooltip(
        message: '#$hex',
        child: InkWell(
          key: ValueKey('$prefix-$hex'),
          onTap: () => Navigator.pop(context, _Colour(rgb)),
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: Color(0xFF000000 | rgb),
              border: Border.all(color: Colors.black26),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton(
          key: const ValueKey('colour-automatic'),
          onPressed: () =>
              Navigator.pop(context, const _Colour(kOfficeAutomaticColour)),
          child: const Text('Automatic'),
        ),
        for (final row in kOfficePalette)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [for (final rgb in row) _swatch(context, rgb)],
          ),
        if (recent.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Recent', style: Theme.of(context).textTheme.labelSmall),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final rgb in recent) _swatch(context, rgb, prefix: 'recent'),
            ],
          ),
        ],
      ],
    ),
    actions: [
      TextButton(
        key: const ValueKey('colour-custom'),
        onPressed: () => Navigator.pop(context, const _Custom()),
        child: const Text('Custom colour…'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ],
  );
}

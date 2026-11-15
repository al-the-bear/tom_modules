import 'package:flutter/material.dart';

/// What kind of editing surface holds the keyboard focus.
///
/// A host — a Forge editor adapter, say — offers different actions depending
/// on it, and the kind is the whole of what it needs to know. It is read from the
/// **real** focus: see [tomFocusedEditingSurface].
enum TomEditingSurfaceKind {
  /// A rich-text body.
  richText,

  /// A spreadsheet cell **editor** — the cell's text field, not the grid.
  /// A grid-level range operation is the grid's action, not a text one.
  sheetCell,

  /// A password field. Clipboard actions are never offered for it: its
  /// reveal / copy / clear are password-domain affordances with auto-clear.
  password,
}

/// The editing commands a surface may perform for a host, closed on purpose:
/// a host maps its own action ids onto these, and a surface answers only
/// these.
enum TomEditingCommand { cut, copy, paste, selectAll }

/// Marks the subtree of a content body that is an editing surface.
///
/// Built by the body itself — a document editor around its rich-text editor,
/// a grid around its cell editor — so a shell and a host can tell which kind
/// of surface the keyboard is in without naming the package that draws it.
/// [perform] runs a command against the surface; null means the surface
/// performs none, whatever its kind.
class TomEditingSurface extends StatelessWidget {
  const TomEditingSurface({
    super.key,
    required this.kind,
    required this.child,
    this.perform,
  });

  final TomEditingSurfaceKind kind;
  final bool Function(TomEditingCommand command)? perform;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// The editing surface the primary focus is in, or null.
///
/// Read from `FocusManager.instance.primaryFocus` — the focus the keyboard
/// actually has, not a flag a body sets — by walking up from the focused
/// node to the nearest [TomEditingSurface]. When [within] is given, a
/// surface outside that subtree does not count: a host asks about its own
/// rendering, not about another pane that happens to hold focus.
///
/// A [TomEditingSurfaceKind.sheetCell] surface counts only while a text
/// field inside it has the focus — the cell editor. Focus on the grid itself is
/// structural.
TomEditingSurface? tomFocusedEditingSurface({BuildContext? within}) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null || !context.mounted) return null;
  if (within != null && !_isWithin(context, within)) return null;
  final surface = context
      .findAncestorWidgetOfExactType<TomEditingSurface>();
  if (surface == null) return null;
  if (surface.kind == TomEditingSurfaceKind.sheetCell &&
      context.widget is! EditableText &&
      context.findAncestorWidgetOfExactType<EditableText>() == null) {
    return null;
  }
  return surface;
}

bool _isWithin(BuildContext context, BuildContext within) {
  if (identical(context, within)) return true;
  var found = false;
  context.visitAncestorElements((element) {
    if (identical(element, within)) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

/// Performs [command] on the text field that has the focus, through the text
/// intents Flutter's own text fields answer — what a cell editor built on a
/// `TextField` passes as its [TomEditingSurface.perform].
bool tomPerformFocusedTextCommand(TomEditingCommand command) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  final Intent intent = switch (command) {
    TomEditingCommand.cut => CopySelectionTextIntent.cut(
      SelectionChangedCause.keyboard,
    ),
    TomEditingCommand.copy => CopySelectionTextIntent.copy,
    TomEditingCommand.paste => const PasteTextIntent(
      SelectionChangedCause.keyboard,
    ),
    TomEditingCommand.selectAll => const SelectAllTextIntent(
      SelectionChangedCause.keyboard,
    ),
  };
  // Found first, because `maybeInvoke` answers with the action's result —
  // null for these — whether or not an action ran.
  if (Actions.maybeFind<Intent>(context, intent: intent) == null) return false;
  Actions.invoke(context, intent);
  return true;
}

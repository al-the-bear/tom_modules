// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The bars both PDF views share: a notice above the document and a
/// toolbar's row. Both fit any width the editor is given.
library;

import 'package:flutter/material.dart';

/// A notice above the document (read-only, encrypted, changed or deleted on
/// disk), with its [actions].
class PdfNoticeBar extends StatelessWidget {
  const PdfNoticeBar({
    super.key,
    required this.icon,
    required this.text,
    this.actions = const [],
  });

  final IconData icon;
  final String text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        // The actions stay beside the text while they fit and move to a
        // line of their own below it in a narrow pane.
        child: Row(
          children: [
            Icon(icon, size: 18, color: scheme.onSecondaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    text,
                    style: TextStyle(color: scheme.onSecondaryContainer),
                  ),
                  if (actions.isNotEmpty)
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: actions,
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

/// A toolbar's row: as wide as the editor, its [Spacer]s taking the room
/// left; scrolled sideways when the editor is narrower than its buttons (a
/// split pane).
class PdfToolbarRow extends StatelessWidget {
  const PdfToolbarRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: constraints.maxWidth),
        child: IntrinsicWidth(child: Row(children: children)),
      ),
    ),
  );
}

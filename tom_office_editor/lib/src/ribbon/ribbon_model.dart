// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The ribbon's tabs, groups and controls per document type
/// (`part-office-editor`, *The ribbon*, DPOE-1). Only commands that work in
/// LibreOfficeKit are listed: those the first spike passed
/// (`spikes/lok_spike.md`, item 9) and those its retest with arguments or a
/// text edit mode passed (officeproto31c): `.uno:InsertSymbol` for the
/// special character, `.uno:InsertPageFooter` with its page style, `.uno:Color`
/// for the font colour, super- and subscript while a cell is edited, and
/// Impress's paragraph, list and colour commands while a text is edited.
/// Left out, failing there: Clone Formatting, Writer's table, chart, comment,
/// margins and columns, Calc's borders, merge, AutoSum and image, and
/// Impress's clipboard commands (the editor's own copy and paste stand in),
/// delete slide, image, chart, shapes, slide setup, comments and notes view.
library;

import 'package:flutter/material.dart';

import 'package:tom_office_protocol/tom_office_protocol.dart'
    show OfficeDocType;

import '../controller.dart';

/// A UNO argument list in LibreOfficeKit's JSON form.
String unoArgs(Map<String, (String type, Object value)> args) {
  final parts = [
    for (final MapEntry(:key, :value) in args.entries)
      '"$key":{"type":"${value.$1}","value":${value.$2 is String ? '"${_escape(value.$2 as String)}"' : value.$2}}',
  ];
  return '{${parts.join(',')}}';
}

String _escape(String s) => s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

/// One control of the ribbon.
@immutable
sealed class RibbonControl {
  const RibbonControl(this.id, this.label, this.icon);

  /// A stable id (`bold`, `fontColour`): the control's key in tests.
  final String id;

  /// What it says (its tooltip).
  final String label;

  /// Its icon.
  final IconData icon;
}

/// A UNO command button; a toggle shows `STATE_CHANGED`'s `true` as
/// checked, and `disabled` disables it.
final class RibbonCommand extends RibbonControl {
  /// A command button.
  const RibbonCommand(
    super.id,
    super.label,
    super.icon,
    this.command, {
    this.args = '',
    this.toggle = false,
    this.dialog = false,
    this.edits = true,
  });

  /// The UNO command, e.g. `.uno:Bold`.
  final String command;

  /// Its JSON arguments.
  final String args;

  /// Whether it shows a checked state.
  final bool toggle;

  /// Whether it opens a LibreOffice dialog.
  final bool dialog;

  /// Whether it changes the document (disabled when read-only).
  final bool edits;
}

/// Where a dropdown's entries come from.
enum RibbonChoiceSource {
  /// The fonts of `getCommandValues('.uno:CharFontName')`.
  fonts,

  /// The sizes of the current font from the same values.
  sizes,

  /// The paragraph styles of `getCommandValues('.uno:StyleApply')`.
  paragraphStyles,

  /// The fixed entries of [RibbonChoice.entries].
  fixed,
}

/// A dropdown that runs [command] with the chosen value.
final class RibbonChoice extends RibbonControl {
  /// A dropdown.
  const RibbonChoice(
    super.id,
    super.label,
    super.icon,
    this.command, {
    required this.source,
    required this.args,
    this.entries = const [],
    this.width = 140,
  });

  /// The UNO command; its `STATE_CHANGED` value is the current entry.
  final String command;

  /// Where the entries come from.
  final RibbonChoiceSource source;

  /// The arguments for an entry's value.
  final String Function(String value) args;

  /// Fixed entries: (value, label).
  final List<(String, String)> entries;

  /// Its width.
  final double width;
}

/// A colour split button: the main part applies the last colour, the arrow
/// opens the colour picker.
final class RibbonColour extends RibbonControl {
  /// A colour button.
  const RibbonColour(
    super.id,
    super.label,
    super.icon,
    this.command,
    this.argument, {
    required this.initial,
    required this.customDialog,
  });

  /// The UNO command, e.g. `.uno:Color`.
  final String command;

  /// Its argument's name (a `long` RGB value; −1 is *Automatic*).
  final String argument;

  /// The colour before one is chosen.
  final int initial;

  /// The properties dialog *Custom colour…* opens (its page holds
  /// *Pick…*, which opens LibreOffice's colour dialog).
  final String customDialog;
}

/// What a local control does (no UNO command of its own).
enum RibbonLocalAction {
  /// The editor's copy (text on the clipboard).
  copy,

  /// The editor's cut.
  cut,

  /// The editor's paste.
  paste,

  /// The host's file picker, then `.uno:InsertGraphic`.
  insertImage,

  /// The view zooms in.
  zoomIn,

  /// The view zooms out.
  zoomOut,
}

/// A control the editor handles itself.
final class RibbonLocal extends RibbonControl {
  /// A local control.
  const RibbonLocal(super.id, super.label, super.icon, this.action);

  /// What it does.
  final RibbonLocalAction action;
}

/// A group of controls.
@immutable
final class RibbonGroup {
  /// A group.
  const RibbonGroup(this.label, this.controls);

  /// Its caption.
  final String label;

  /// Its controls.
  final List<RibbonControl> controls;
}

/// A tab.
@immutable
final class RibbonTab {
  /// A tab.
  const RibbonTab(this.label, this.groups);

  /// Its label.
  final String label;

  /// Its groups.
  final List<RibbonGroup> groups;
}

// ---------------------------------------------------------------- controls

const _clipboard = RibbonGroup('Clipboard', [
  RibbonLocal('paste', 'Paste', Icons.content_paste, RibbonLocalAction.paste),
  RibbonLocal('cut', 'Cut', Icons.content_cut, RibbonLocalAction.cut),
  RibbonLocal('copy', 'Copy', Icons.content_copy, RibbonLocalAction.copy),
]);

String _fontArgs(String v) =>
    unoArgs({'CharFontName.FamilyName': ('string', v)});

String _sizeArgs(String v) =>
    unoArgs({'FontHeight.Height': ('float', double.tryParse(v) ?? 12)});

final _fontName = RibbonChoice(
  'fontName',
  'Font',
  Icons.font_download_outlined,
  '.uno:CharFontName',
  source: RibbonChoiceSource.fonts,
  args: _fontArgs,
  width: 170,
);

final _fontSize = RibbonChoice(
  'fontSize',
  'Size',
  Icons.format_size,
  '.uno:FontHeight',
  source: RibbonChoiceSource.sizes,
  args: _sizeArgs,
  width: 70,
);

const _bold = RibbonCommand(
  'bold',
  'Bold',
  Icons.format_bold,
  '.uno:Bold',
  toggle: true,
);
const _italic = RibbonCommand(
  'italic',
  'Italic',
  Icons.format_italic,
  '.uno:Italic',
  toggle: true,
);
const _underline = RibbonCommand(
  'underline',
  'Underline',
  Icons.format_underline,
  '.uno:Underline',
  toggle: true,
);
const _strike = RibbonCommand(
  'strikethrough',
  'Strikethrough',
  Icons.format_strikethrough,
  '.uno:Strikeout',
  toggle: true,
);
const _superscript = RibbonCommand(
  'superscript',
  'Superscript',
  Icons.superscript,
  '.uno:SuperScript',
  toggle: true,
);
const _subscript = RibbonCommand(
  'subscript',
  'Subscript',
  Icons.subscript,
  '.uno:SubScript',
  toggle: true,
);

RibbonColour _fontColour(String dialog) => RibbonColour(
  'fontColour',
  'Font colour',
  Icons.format_color_text,
  '.uno:Color',
  'Color',
  initial: 0xC9211E,
  customDialog: dialog,
);

const _alignLeft = RibbonCommand(
  'alignLeft',
  'Align left',
  Icons.format_align_left,
  '.uno:LeftPara',
  toggle: true,
);
const _alignCentre = RibbonCommand(
  'alignCentre',
  'Centre',
  Icons.format_align_center,
  '.uno:CenterPara',
  toggle: true,
);
const _alignRight = RibbonCommand(
  'alignRight',
  'Align right',
  Icons.format_align_right,
  '.uno:RightPara',
  toggle: true,
);
const _justify = RibbonCommand(
  'justify',
  'Justified',
  Icons.format_align_justify,
  '.uno:JustifyPara',
  toggle: true,
);
const _bullets = RibbonCommand(
  'bullets',
  'Bullets',
  Icons.format_list_bulleted,
  '.uno:DefaultBullet',
  toggle: true,
);
const _numbering = RibbonCommand(
  'numbering',
  'Numbering',
  Icons.format_list_numbered,
  '.uno:DefaultNumbering',
  toggle: true,
);
const _paragraphDialog = RibbonCommand(
  'paragraphDialog',
  'Paragraph…',
  Icons.notes,
  '.uno:ParagraphDialog',
  dialog: true,
);
const _find = RibbonCommand(
  'find',
  'Find & Replace…',
  Icons.find_replace,
  '.uno:SearchDialog',
  dialog: true,
  edits: false,
);
const _hyperlink = RibbonCommand(
  'hyperlink',
  'Hyperlink…',
  Icons.link,
  '.uno:HyperlinkDialog',
  dialog: true,
);
const _zoom = RibbonGroup('Zoom', [
  RibbonLocal('zoomOut', 'Zoom out', Icons.zoom_out, RibbonLocalAction.zoomOut),
  RibbonLocal('zoomIn', 'Zoom in', Icons.zoom_in, RibbonLocalAction.zoomIn),
]);
const _spelling = RibbonCommand(
  'spelling',
  'Spelling…',
  Icons.spellcheck,
  '.uno:SpellDialog',
  dialog: true,
);

/// Writer's line spacings.
const kLineSpacings = [
  ('.uno:SpacePara1', '1'),
  ('.uno:SpacePara15', '1.5'),
  ('.uno:SpacePara2', '2'),
];

/// Impress's slide layouts (`.uno:AssignLayout`, `WhatLayout`: the
/// AutoLayout numbers).
const kSlideLayouts = [
  ('20', 'Blank'),
  ('0', 'Title slide'),
  ('1', 'Title, content'),
  ('3', 'Title, 2 contents'),
  ('19', 'Title only'),
  ('32', 'Centred text'),
];

// -------------------------------------------------------------- the tabs

List<RibbonTab> _text() => [
  RibbonTab('Home', [
    _clipboard,
    RibbonGroup('Font', [
      _fontName,
      _fontSize,
      _bold,
      _italic,
      _underline,
      _strike,
      _superscript,
      _subscript,
      _fontColour('.uno:FontDialog'),
      const RibbonColour(
        'highlight',
        'Highlighting',
        Icons.border_color,
        '.uno:CharBackColor',
        'CharBackColor',
        initial: 0xFFFF00,
        customDialog: '.uno:FontDialog',
      ),
      const RibbonCommand(
        'clearFormatting',
        'Clear formatting',
        Icons.format_clear,
        '.uno:ResetAttributes',
      ),
      const RibbonCommand(
        'characterDialog',
        'Character…',
        Icons.text_format,
        '.uno:FontDialog',
        dialog: true,
      ),
    ]),
    RibbonGroup('Paragraph', [
      _alignLeft,
      _alignCentre,
      _alignRight,
      _justify,
      _bullets,
      _numbering,
      const RibbonCommand(
        'indentMore',
        'Increase indent',
        Icons.format_indent_increase,
        '.uno:IncrementIndent',
      ),
      const RibbonCommand(
        'indentLess',
        'Decrease indent',
        Icons.format_indent_decrease,
        '.uno:DecrementIndent',
      ),
      RibbonChoice(
        'lineSpacing',
        'Line spacing',
        Icons.format_line_spacing,
        '',
        source: RibbonChoiceSource.fixed,
        args: (_) => '',
        entries: kLineSpacings,
        width: 70,
      ),
      _paragraphDialog,
    ]),
    RibbonGroup('Styles', [
      RibbonChoice(
        'paragraphStyle',
        'Paragraph style',
        Icons.style,
        '.uno:StyleApply',
        source: RibbonChoiceSource.paragraphStyles,
        args: (v) => unoArgs({
          'Style': ('string', v),
          'FamilyName': ('string', 'ParagraphStyles'),
        }),
        width: 170,
      ),
    ]),
    const RibbonGroup('Editing', [_find]),
  ]),
  const RibbonTab('Insert', [
    RibbonGroup('Insert', [
      RibbonLocal(
        'image',
        'Image…',
        Icons.image_outlined,
        RibbonLocalAction.insertImage,
      ),
      _hyperlink,
      RibbonCommand(
        'pageBreak',
        'Page break',
        Icons.insert_page_break,
        '.uno:InsertPagebreak',
      ),
      RibbonCommand(
        'specialCharacter',
        'Special character…',
        Icons.emoji_symbols,
        '.uno:InsertSymbol',
        dialog: true,
      ),
      RibbonCommand(
        'pageNumber',
        'Page number',
        Icons.numbers,
        '.uno:InsertPageNumberField',
      ),
    ]),
    RibbonGroup('Header & Footer', [
      RibbonCommand(
        'header',
        'Header',
        Icons.vertical_align_top,
        '.uno:InsertPageHeader',
        args:
            '{"PageStyle":{"type":"string","value":"Default Page Style"},'
            '"On":{"type":"boolean","value":true}}',
      ),
      RibbonCommand(
        'footer',
        'Footer',
        Icons.vertical_align_bottom,
        '.uno:InsertPageFooter',
        args:
            '{"PageStyle":{"type":"string","value":"Default Page Style"},'
            '"On":{"type":"boolean","value":true}}',
      ),
    ]),
  ]),
  const RibbonTab('Layout', [
    RibbonGroup('Page', [
      RibbonCommand(
        'pageStyle',
        'Page style…',
        Icons.description_outlined,
        '.uno:PageDialog',
        dialog: true,
      ),
      RibbonCommand(
        'orientation',
        'Orientation',
        Icons.screen_rotation_alt,
        '.uno:Orientation',
      ),
    ]),
  ]),
  const RibbonTab('Review', [
    RibbonGroup('Proofing', [
      RibbonCommand(
        'spelling',
        'Spelling…',
        Icons.spellcheck,
        '.uno:SpellingAndGrammarDialog',
        dialog: true,
      ),
      RibbonCommand(
        'wordCount',
        'Word count…',
        Icons.numbers,
        '.uno:WordCountDialog',
        dialog: true,
        edits: false,
      ),
    ]),
    RibbonGroup('Changes', [
      RibbonCommand(
        'trackChanges',
        'Track changes',
        Icons.track_changes,
        '.uno:TrackChanges',
        toggle: true,
      ),
      RibbonCommand(
        'acceptChange',
        'Accept change',
        Icons.check,
        '.uno:AcceptTrackedChange',
      ),
      RibbonCommand(
        'rejectChange',
        'Reject change',
        Icons.close,
        '.uno:RejectTrackedChange',
      ),
    ]),
  ]),
  const RibbonTab('View', [
    _zoom,
    RibbonGroup('Show', [
      RibbonCommand(
        'formattingMarks',
        'Formatting marks',
        Icons.subject,
        '.uno:ControlCodes',
        toggle: true,
        edits: false,
      ),
      RibbonCommand(
        'webLayout',
        'Web layout',
        Icons.web,
        '.uno:BrowseView',
        edits: false,
      ),
      RibbonCommand(
        'printLayout',
        'Print layout',
        Icons.print_outlined,
        '.uno:PrintLayout',
        edits: false,
      ),
    ]),
  ]),
];

List<RibbonTab> _sheet() => [
  RibbonTab('Home', [
    _clipboard,
    RibbonGroup('Font', [
      _fontName,
      _fontSize,
      _bold,
      _italic,
      _underline,
      _strike,
      _superscript,
      _subscript,
      _fontColour('.uno:FormatCellDialog'),
      const RibbonColour(
        'backgroundColour',
        'Background colour',
        Icons.format_color_fill,
        '.uno:BackgroundColor',
        'BackgroundColor',
        initial: 0xFFFF00,
        customDialog: '.uno:FormatCellDialog',
      ),
    ]),
    const RibbonGroup('Alignment', [
      RibbonCommand(
        'alignLeft',
        'Align left',
        Icons.format_align_left,
        '.uno:AlignLeft',
        toggle: true,
      ),
      RibbonCommand(
        'alignCentre',
        'Centre',
        Icons.format_align_center,
        '.uno:AlignHorizontalCenter',
        toggle: true,
      ),
      RibbonCommand(
        'alignRight',
        'Align right',
        Icons.format_align_right,
        '.uno:AlignRight',
        toggle: true,
      ),
      RibbonCommand(
        'alignTop',
        'Align top',
        Icons.vertical_align_top,
        '.uno:AlignTop',
      ),
      RibbonCommand(
        'alignMiddle',
        'Align middle',
        Icons.vertical_align_center,
        '.uno:AlignVCenter',
      ),
      RibbonCommand(
        'alignBottom',
        'Align bottom',
        Icons.vertical_align_bottom,
        '.uno:AlignBottom',
      ),
      RibbonCommand(
        'wrapText',
        'Wrap text',
        Icons.wrap_text,
        '.uno:WrapText',
        toggle: true,
      ),
    ]),
    const RibbonGroup('Number', [
      RibbonCommand(
        'numberStandard',
        'General',
        Icons.tag,
        '.uno:NumberFormatStandard',
      ),
      RibbonCommand(
        'numberCurrency',
        'Currency',
        Icons.attach_money,
        '.uno:NumberFormatCurrency',
        toggle: true,
      ),
      RibbonCommand(
        'numberPercent',
        'Percent',
        Icons.percent,
        '.uno:NumberFormatPercent',
        toggle: true,
      ),
      RibbonCommand(
        'decimalsMore',
        'Add decimal place',
        Icons.exposure_plus_1,
        '.uno:NumberFormatIncDecimals',
      ),
      RibbonCommand(
        'decimalsLess',
        'Delete decimal place',
        Icons.exposure_neg_1,
        '.uno:NumberFormatDecDecimals',
      ),
      RibbonCommand(
        'formatCells',
        'Format Cells…',
        Icons.grid_on,
        '.uno:FormatCellDialog',
        dialog: true,
      ),
    ]),
    const RibbonGroup('Cells', [
      RibbonCommand(
        'insertRows',
        'Insert rows below',
        Icons.table_rows_outlined,
        '.uno:InsertRowsAfter',
      ),
      RibbonCommand(
        'insertColumns',
        'Insert columns right',
        Icons.view_column_outlined,
        '.uno:InsertColumnsAfter',
      ),
      RibbonCommand(
        'deleteRows',
        'Delete rows',
        Icons.playlist_remove,
        '.uno:DeleteRows',
      ),
      RibbonCommand(
        'deleteColumns',
        'Delete columns',
        Icons.remove_circle_outline,
        '.uno:DeleteColumns',
      ),
      _find,
    ]),
  ]),
  const RibbonTab('Insert', [
    RibbonGroup('Insert', [
      RibbonCommand(
        'function',
        'Function…',
        Icons.functions,
        '.uno:FunctionDialog',
        dialog: true,
      ),
      RibbonCommand(
        'chart',
        'Chart…',
        Icons.bar_chart,
        '.uno:InsertObjectChart',
        dialog: true,
      ),
      RibbonCommand(
        'comment',
        'Comment',
        Icons.comment_outlined,
        '.uno:InsertAnnotation',
      ),
      _hyperlink,
    ]),
  ]),
  const RibbonTab('Layout', [
    RibbonGroup('Sheet', [
      RibbonCommand(
        'freezePanes',
        'Freeze panes',
        Icons.ac_unit,
        '.uno:FreezePanes',
        toggle: true,
      ),
      RibbonCommand(
        'rowHeight',
        'Row height…',
        Icons.height,
        '.uno:RowHeight',
        dialog: true,
      ),
      RibbonCommand(
        'columnWidth',
        'Column width…',
        Icons.width_normal,
        '.uno:ColumnWidth',
        dialog: true,
      ),
      RibbonCommand(
        'insertSheet',
        'Insert sheet…',
        Icons.add_box_outlined,
        '.uno:Insert',
        dialog: true,
      ),
      RibbonCommand(
        'deleteSheet',
        'Delete sheet…',
        Icons.delete_outline,
        '.uno:Remove',
        dialog: true,
      ),
      RibbonCommand(
        'renameSheet',
        'Rename sheet…',
        Icons.drive_file_rename_outline,
        '.uno:RenameTable',
        dialog: true,
      ),
    ]),
  ]),
  const RibbonTab('Data', [
    RibbonGroup('Sort & Filter', [
      RibbonCommand(
        'sortAscending',
        'Sort ascending',
        Icons.arrow_upward,
        '.uno:SortAscending',
      ),
      RibbonCommand(
        'sortDescending',
        'Sort descending',
        Icons.arrow_downward,
        '.uno:SortDescending',
      ),
      RibbonCommand(
        'sortDialog',
        'Sort…',
        Icons.sort,
        '.uno:DataSort',
        dialog: true,
      ),
      RibbonCommand(
        'autoFilter',
        'AutoFilter',
        Icons.filter_alt_outlined,
        '.uno:DataFilterAutoFilter',
        toggle: true,
      ),
      RibbonCommand(
        'validity',
        'Validity…',
        Icons.rule,
        '.uno:Validation',
        dialog: true,
      ),
    ]),
  ]),
  const RibbonTab('Review', [
    RibbonGroup('Proofing', [_spelling]),
  ]),
  const RibbonTab('View', [
    _zoom,
    RibbonGroup('Show', [
      RibbonCommand(
        'gridLines',
        'Grid lines',
        Icons.grid_4x4,
        '.uno:ToggleSheetGrid',
        toggle: true,
        edits: false,
      ),
      RibbonCommand(
        'headers',
        'Headers',
        Icons.border_top,
        '.uno:ViewRowColumnHeaders',
        edits: false,
      ),
    ]),
  ]),
];

List<RibbonTab> _presentation() => [
  RibbonTab('Home', [
    _clipboard,
    RibbonGroup('Font', [
      _fontName,
      _fontSize,
      _bold,
      _italic,
      _underline,
      _strike,
      _superscript,
      _subscript,
      _fontColour('.uno:FontDialog'),
    ]),
    const RibbonGroup('Paragraph', [
      _alignLeft,
      _alignCentre,
      _alignRight,
      _justify,
      _bullets,
      _numbering,
      _paragraphDialog,
    ]),
    RibbonGroup('Slides', [
      const RibbonCommand(
        'newSlide',
        'New slide',
        Icons.add_to_photos_outlined,
        '.uno:InsertPage',
      ),
      const RibbonCommand(
        'duplicateSlide',
        'Duplicate slide',
        Icons.copy_all,
        '.uno:DuplicatePage',
      ),
      RibbonChoice(
        'slideLayout',
        'Layout',
        Icons.dashboard_outlined,
        '.uno:AssignLayout',
        source: RibbonChoiceSource.fixed,
        args: (v) => unoArgs({'WhatLayout': ('long', int.parse(v))}),
        entries: kSlideLayouts,
      ),
    ]),
  ]),
  const RibbonTab('Insert', [
    RibbonGroup('Insert', [
      RibbonCommand('textBox', 'Text box', Icons.text_fields, '.uno:Text'),
      RibbonCommand(
        'table',
        'Table…',
        Icons.table_chart_outlined,
        '.uno:InsertTable',
        dialog: true,
      ),
      _hyperlink,
    ]),
  ]),
  const RibbonTab('Review', [
    RibbonGroup('Proofing', [_spelling]),
  ]),
  const RibbonTab('View', [_zoom]),
];

/// The ribbon's tabs for a document of [type].
List<RibbonTab> officeRibbonTabs(OfficeDocType type) => switch (type) {
  OfficeDocType.text => _text(),
  OfficeDocType.spreadsheet => _sheet(),
  OfficeDocType.presentation || OfficeDocType.drawing => _presentation(),
  OfficeDocType.other => _text(),
};

/// LibreOffice's Standard palette (`standard.soc`): its grey row and the
/// twelve hues in their standard, dark and light shades. LibreOffice
/// 26.8.3.1 offers no palette through `getCommandValues`, so the picker
/// carries it.
const kOfficePalette = <List<int>>[
  [
    0x000000, 0x111111, 0x1C1C1C, 0x333333, 0x666666, 0x808080, //
    0x999999, 0xB2B2B2, 0xCCCCCC, 0xDDDDDD, 0xEEEEEE, 0xFFFFFF,
  ],
  [
    0xFFFF00, 0xFFBF00, 0xFF8000, 0xFF4000, 0xFF0000, 0xBF0041, //
    0x800080, 0x55308D, 0x2A6099, 0x158466, 0x00A933, 0x81D41A,
  ],
  [
    0xFFFFD7, 0xFFF5CE, 0xFFDBB6, 0xFFD8CE, 0xFFD7D7, 0xF7D1D5, //
    0xE0C2CD, 0xDEDCE6, 0xDEE6EF, 0xDEE7E5, 0xDDE8CB, 0xF6F9D4,
  ],
  [
    0xFFFFA6, 0xFFE994, 0xFFB66C, 0xFFAA95, 0xFFA6A6, 0xEC9BA4, //
    0xBF819E, 0xB7B3CA, 0xB4C7DC, 0xB3CAC7, 0xAFD095, 0xE8F2A1,
  ],
  [
    0xFFFF6D, 0xFFDE59, 0xFF972F, 0xFF7B59, 0xFF6D6D, 0xE16173, //
    0xA1467E, 0x8E86AE, 0x729FCF, 0x81ACA6, 0x77BC65, 0xD4EA6B,
  ],
  [
    0xFFFF38, 0xFFD428, 0xFF860D, 0xFF5429, 0xFF3838, 0xD62E4E, //
    0x8D1D75, 0x6B5E9B, 0x5983B0, 0x50938A, 0x3FAF46, 0xD1E67E,
  ],
  [
    0xC9211E, 0xB47804, 0xB85C00, 0xBE480A, 0xC9211E, 0x861141, //
    0x650953, 0x43215B, 0x355269, 0x1E6A39, 0x127622, 0x468A1A,
  ],
  [
    0x8D281E, 0x784B04, 0x7B3D00, 0x813709, 0x8D281E, 0x611729, //
    0x4E102D, 0x481D32, 0x383D3C, 0x28471F, 0x224B12, 0x395511,
  ],
];

/// *Automatic*: LibreOffice's `COL_AUTO` as a `long`.
const kOfficeAutomaticColour = -1;

/// The colours [controller] chose recently, newest first (the picker's
/// recent row).
List<int> recentColours(TomOfficeEditorController controller) =>
    controller.recentColours;

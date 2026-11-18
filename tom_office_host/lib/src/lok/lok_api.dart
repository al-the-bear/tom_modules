// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// What the helper needs of LibreOfficeKit, as Dart interfaces: the FFI
/// implementation (`ffi_lok.dart`) and the tests' fake both implement them,
/// so the frame loop and the dispatch run without LibreOffice.
library;

import 'dart:typed_data';

/// LibreOfficeKit's callback type numbers (`LOK_CALLBACK_*`,
/// `LibreOfficeKitEnums.h`) the helper treats specially, and the names of all
/// it forwards.
abstract final class LokCallbackType {
  /// `LOK_CALLBACK_STATE_CHANGED`.
  static const stateChanged = 8;

  /// `LOK_CALLBACK_UNO_COMMAND_RESULT`.
  static const unoCommandResult = 16;

  /// `LOK_CALLBACK_DOCUMENT_PASSWORD`.
  static const documentPassword = 20;

  /// `LOK_CALLBACK_DOCUMENT_PASSWORD_TO_MODIFY`.
  static const documentPasswordToModify = 21;

  /// `LOK_CALLBACK_WINDOW`.
  static const window = 36;

  /// `LOK_CALLBACK_JSDIALOG` (not in the desktop build's headers; kept for a
  /// LibreOffice that sends it).
  static const jsDialog = 46;

  /// The `LOK_CALLBACK_*` name without the prefix, by number, as the vendored
  /// headers number them (generated from `LibreOfficeKitEnums.h`; the test
  /// `LOK-NAMES-1` checks them).
  static const names = <int, String>{
    0: 'INVALIDATE_TILES',
    1: 'INVALIDATE_VISIBLE_CURSOR',
    2: 'TEXT_SELECTION',
    3: 'TEXT_SELECTION_START',
    4: 'TEXT_SELECTION_END',
    5: 'CURSOR_VISIBLE',
    6: 'GRAPHIC_SELECTION',
    7: 'HYPERLINK_CLICKED',
    8: 'STATE_CHANGED',
    9: 'STATUS_INDICATOR_START',
    10: 'STATUS_INDICATOR_SET_VALUE',
    11: 'STATUS_INDICATOR_FINISH',
    12: 'SEARCH_NOT_FOUND',
    13: 'DOCUMENT_SIZE_CHANGED',
    14: 'SET_PART',
    15: 'SEARCH_RESULT_SELECTION',
    16: 'UNO_COMMAND_RESULT',
    17: 'CELL_CURSOR',
    18: 'MOUSE_POINTER',
    19: 'CELL_FORMULA',
    20: 'DOCUMENT_PASSWORD',
    21: 'DOCUMENT_PASSWORD_TO_MODIFY',
    22: 'ERROR',
    23: 'CONTEXT_MENU',
    24: 'INVALIDATE_VIEW_CURSOR',
    25: 'TEXT_VIEW_SELECTION',
    26: 'CELL_VIEW_CURSOR',
    27: 'GRAPHIC_VIEW_SELECTION',
    28: 'VIEW_CURSOR_VISIBLE',
    29: 'VIEW_LOCK',
    30: 'REDLINE_TABLE_SIZE_CHANGED',
    31: 'REDLINE_TABLE_ENTRY_MODIFIED',
    32: 'COMMENT',
    33: 'INVALIDATE_HEADER',
    34: 'CELL_ADDRESS',
    35: 'RULER_UPDATE',
    36: 'WINDOW',
    37: 'VALIDITY_LIST_BUTTON',
    38: 'CLIPBOARD_CHANGED',
    39: 'CONTEXT_CHANGED',
    40: 'SIGNATURE_STATUS',
    41: 'PROFILE_FRAME',
    42: 'CELL_SELECTION_AREA',
    43: 'CELL_AUTO_FILL_AREA',
    44: 'TABLE_SELECTED',
    45: 'REFERENCE_MARKS',
    46: 'JSDIALOG', // upstream's number; not in these headers
    47: 'CALC_FUNCTION_LIST',
    48: 'TAB_STOP_LIST',
    49: 'FORM_FIELD_BUTTON',
    50: 'INVALIDATE_SHEET_GEOMETRY',
    51: 'VALIDITY_INPUT_HELP',
    52: 'DOCUMENT_BACKGROUND_COLOR',
    54: 'SC_FOLLOW_JUMP',
    55: 'CONTENT_CONTROL',
    56: 'PRINT_RANGES',
    57: 'FONTS_MISSING',
    58: 'MEDIA_SHAPE',
    59: 'EXPORT_FILE',
    60: 'VIEW_RENDER_STATE',
    61: 'APPLICATION_BACKGROUND_COLOR',
    62: 'A11Y_FOCUS_CHANGED',
    63: 'A11Y_CARET_CHANGED',
    64: 'A11Y_TEXT_SELECTION_CHANGED',
    66: 'DOCUMENT_PASSWORD_RESET',
    67: 'A11Y_FOCUSED_CELL_CHANGED',
    68: 'A11Y_EDITING_IN_SELECTION_STATE',
    69: 'A11Y_SELECTION_CHANGED',
    70: 'CORE_LOG',
    71: 'TOOLTIP',
    72: 'SHAPE_INNER_TEXT',
    73: 'VERTICAL_RULER_UPDATE',
  };

  /// The name of callback [type], `TYPE_<n>` for one not listed.
  static String nameOf(int type) => names[type] ?? 'TYPE_$type';
}

/// One callback as the trampoline handed it over: its type and payload.
final class LokCallback {
  /// A callback from its parts.
  const LokCallback(this.type, this.payload);

  /// The `LOK_CALLBACK_*` number.
  final int type;

  /// The payload, copied before LibreOfficeKit freed it.
  final String payload;

  @override
  String toString() => '${LokCallbackType.nameOf(type)} $payload';
}

/// Loads LibreOfficeKit and delivers its callbacks.
abstract interface class LokRuntime {
  /// Every callback of the office and its document, in order.
  Stream<LokCallback> get callbacks;

  /// `lok_init_2` on the program folder [program] with the profile
  /// [profileUrl] (`file://`); `null` when LibreOfficeKit does not load.
  LokOffice? init(String program, String profileUrl);

  /// Which password kinds were asked for since the last
  /// [LokOffice.armPasswordAnswer]: bit 0 to open, bit 1 to modify, bit 2 a
  /// second request after the armed answer was used (a wrong password).
  int get passwordAsked;
}

/// The office (`LibreOfficeKit`).
abstract interface class LokOffice {
  /// `getVersionInfo`: the version JSON.
  String get versionInfo;

  /// `setOptionalFeatures`.
  void setOptionalFeatures(int features);

  /// Arms the answer the trampoline gives to the next password request
  /// (`null`: cancel). Never logged.
  void armPasswordAnswer(String? password);

  /// `documentLoadWithOptions` of the file at [path]; `null` when it fails
  /// ([lastError] says why).
  LokDocument? load(String path, String optionsJson);

  /// `getError`, or `null`.
  String? lastError();

  /// `destroy`.
  void destroy();
}

/// One document (`LibreOfficeKitDocument`). Positions are twips in the
/// document, pixels in a window.
abstract interface class LokDocument {
  /// `getDocumentType`: 0 text, 1 spreadsheet, 2 presentation, 3 drawing,
  /// 4 other.
  int get documentType;

  /// `getParts`.
  int get parts;

  /// `getPart`.
  int get part;

  /// `setPart`.
  set part(int value);

  /// `getPartName`.
  String partName(int part);

  /// `getTileMode`: 0 RGBA, 1 BGRA.
  int get tileMode;

  /// `getDocumentSize` in twips.
  (int, int) get size;

  /// `initializeForRendering`.
  void initializeForRendering(String argumentsJson);

  /// `setClientZoom`.
  void setClientZoom(int tilePxW, int tilePxH, int tileTwW, int tileTwH);

  /// `setClientVisibleArea`.
  void setClientVisibleArea(int x, int y, int w, int h);

  /// `paintPartTile` (`paintTile` for a document of one part): `pxW × pxH`
  /// pixels, 4 bytes each, of the twip area x, y, w, h of [part].
  Uint8List paintTile(int part, int pxW, int pxH, int x, int y, int w, int h);

  /// `postKeyEvent`.
  void postKeyEvent(int type, int charCode, int keyCode);

  /// Input-method text in the document (`postWindowExtTextInputEvent` on
  /// window 0); false when this LibreOffice lacks the call.
  bool postExtTextInput(int type, String text);

  /// `postMouseEvent`.
  void postMouseEvent(int type, int x, int y, int count, int buttons, int mods);

  /// `setTextSelection`.
  void setTextSelection(int type, int x, int y);

  /// `setGraphicSelection`.
  void setGraphicSelection(int type, int x, int y);

  /// `resetSelection`.
  void resetSelection();

  /// `getTextSelection` as [mimeType], or `null`.
  String? textSelection(String mimeType);

  /// `paste`.
  bool paste(String mimeType, String data);

  /// `postUnoCommand` with `notifyWhenFinished`, from another thread (a
  /// second isolate): some dialogs run modally inside it and block the
  /// calling thread until they close.
  Future<void> postUnoCommand(String command, String argumentsJson);

  /// `getCommandValues`, or `null`.
  String? commandValues(String command);

  /// `saveAs`: true on success.
  bool saveAs(String path, String format, String filterOptions);

  /// `paintWindow` (`paintWindowDPI` with [dpiScale] other than 1): `w × h`
  /// pixels, 4 bytes each.
  Uint8List paintWindow(
    int windowId,
    int x,
    int y,
    int w,
    int h,
    double dpiScale,
  );

  /// `postWindow` (`LOK_WINDOW_CLOSE` is 0).
  void postWindow(int windowId, int action);

  /// `postWindowKeyEvent`.
  void postWindowKeyEvent(int windowId, int type, int charCode, int keyCode);

  /// `postWindowMouseEvent`.
  void postWindowMouseEvent(
    int windowId,
    int type,
    int x,
    int y,
    int count,
    int buttons,
    int mods,
  );

  /// `postWindowExtTextInputEvent`.
  void postWindowExtTextInput(int windowId, int type, String text);

  /// `destroy`.
  void destroy();
}

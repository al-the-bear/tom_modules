import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'errors.dart';

/// The protocol number this library speaks, sent in [OfficeHello.protocol].
const kOfficeProtocolVersion = 1;

/// Every message type of protocol 1, with the byte that names it in a frame
/// and its name in the working document's table.
///
/// The codes are fixed for protocol 1: a type is only ever added (with a new
/// code), never renumbered or reused.
enum OfficeMessageType {
  hello(1, OfficeDirection.toForge),
  open(2, OfficeDirection.toHelper),
  opened(3, OfficeDirection.toForge),
  passwordNeeded(4, OfficeDirection.toForge),
  password(5, OfficeDirection.toHelper),
  renderTile(6, OfficeDirection.toHelper),
  tile(7, OfficeDirection.toForge),
  key(8, OfficeDirection.toHelper),
  textInput(9, OfficeDirection.toHelper),
  mouse(10, OfficeDirection.toHelper),
  selection(11, OfficeDirection.toHelper),
  uno(12, OfficeDirection.toHelper),
  commandValues(13, OfficeDirection.toHelper),
  valuesReply(14, OfficeDirection.toForge),
  view(15, OfficeDirection.toHelper),
  setPart(16, OfficeDirection.toHelper),
  callback(17, OfficeDirection.toForge),
  save(18, OfficeDirection.toHelper),
  saved(19, OfficeDirection.toForge),
  windowOpened(20, OfficeDirection.toForge),
  windowChanged(21, OfficeDirection.toForge),
  paintWindow(22, OfficeDirection.toHelper),
  windowPixels(23, OfficeDirection.toForge),
  windowMouse(24, OfficeDirection.toHelper),
  windowKey(25, OfficeDirection.toHelper),
  windowTextInput(26, OfficeDirection.toHelper),
  windowClose(27, OfficeDirection.toHelper),
  jsDialog(28, OfficeDirection.toForge),
  dialogEvent(29, OfficeDirection.toHelper),
  dialogMode(30, OfficeDirection.toHelper),
  ping(31, OfficeDirection.toHelper),
  pong(32, OfficeDirection.toForge),
  close(33, OfficeDirection.toHelper),
  closed(34, OfficeDirection.toForge),
  error(35, OfficeDirection.toForge),
  copy(36, OfficeDirection.toHelper),
  clipboard(37, OfficeDirection.toForge),
  paste(38, OfficeDirection.toHelper);

  const OfficeMessageType(this.code, this.direction);

  /// The byte that names the type in a frame.
  final int code;

  /// Which way the message travels.
  final OfficeDirection direction;

  /// The message's name in the working document's table. It is the enum
  /// name, except `values` (an enum cannot have a value of that name).
  String get tableName => this == valuesReply ? 'values' : name;

  static final _byCode = {for (final t in values) t.code: t};

  /// The type named by [code], or `null` when protocol 1 has none.
  static OfficeMessageType? fromCode(int code) => _byCode[code];
}

/// Which way a message travels.
enum OfficeDirection {
  /// From Forge (the office editor) to the helper.
  toHelper,

  /// From the helper to Forge.
  toForge,
}

/// The kind of document `opened` reports (`getDocumentType`).
enum OfficeDocType { text, spreadsheet, presentation, drawing, other }

/// The pixel format of tile and window pixels: 4 bytes per pixel.
enum OfficePixelFormat { bgra, rgba }

/// A key event's type: `postKeyEvent`'s key input (down) or key up.
enum OfficeKeyEventType { down, up }

/// A text input event's type: composing text (`input`) or its end (`end`).
enum OfficeTextInputType { input, end }

/// A mouse event's type: button down, button up, move.
enum OfficeMouseEventType { down, up, move }

/// What a `selection` message moves: a text selection's handle, a graphic
/// selection's handle, or the selection reset.
enum OfficeSelectionKind { text, graphic, reset }

/// How LibreOffice's dialogs are shown: as windows painted by LibreOffice, or
/// as JSON widget trees built as Forge forms.
enum OfficeDialogMode { window, json }

/// A rectangle: twips in document coordinates, pixels in a window.
@immutable
final class OfficeRect {
  /// A rectangle from its corner and size.
  const OfficeRect(this.x, this.y, this.w, this.h);

  /// The left edge.
  final int x;

  /// The top edge.
  final int y;

  /// The width.
  final int w;

  /// The height.
  final int h;

  /// The JSON form, `{x, y, w, h}`.
  Map<String, Object?> toJson() => {'x': x, 'y': y, 'w': w, 'h': h};

  /// The rectangle from [toJson]'s form.
  factory OfficeRect.fromJson(Object? json, String field) {
    final map = _Fields(_asMap(json, field), 'rect');
    return OfficeRect(
      map.int_('x'),
      map.int_('y'),
      map.int_('w'),
      map.int_('h'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OfficeRect &&
      other.x == x &&
      other.y == y &&
      other.w == w &&
      other.h == h;

  @override
  int get hashCode => Object.hash(x, y, w, h);

  @override
  String toString() => 'OfficeRect($x, $y, $w, $h)';
}

/// One message of protocol 1.
///
/// Messages are values: two are equal when they have the same type, the same
/// fields and the same pixel bytes. JSON-valued fields (`lokVersion`, `args`,
/// `json`) are carried as the JSON text LibreOfficeKit takes or gives, not
/// parsed, so they pass through unchanged.
@immutable
sealed class OfficeMessage {
  const OfficeMessage();

  /// The message's type in the protocol's table.
  OfficeMessageType get messageType;

  /// The JSON header of its frame: every field except the pixel bytes.
  Map<String, Object?> toJson();

  /// The raw bytes after the header: the pixels of `tile` and
  /// `windowPixels`, empty for every other message.
  Uint8List get bytes => _empty;

  static final _empty = Uint8List(0);

  /// The message of [type] from its frame's header and raw bytes.
  ///
  /// Throws [OfficeProtocolException] when a required field is missing or of
  /// the wrong kind. Unknown fields are ignored: protocol 1 only ever adds
  /// fields.
  static OfficeMessage fromJson(
    OfficeMessageType type,
    Map<String, Object?> json, [
    Uint8List? bytes,
  ]) {
    final f = _Fields(json, type.tableName);
    final pixels = bytes ?? _empty;
    if (pixels.isNotEmpty &&
        type != OfficeMessageType.tile &&
        type != OfficeMessageType.windowPixels) {
      throw OfficeProtocolException(
        OfficeProtocolErrorCode.malformed,
        '${type.tableName} carries no raw bytes, got ${pixels.length}',
      );
    }
    return switch (type) {
      OfficeMessageType.hello => OfficeHello(
        protocol: f.int_('protocol'),
        helperVersion: f.string('helperVersion'),
        lokVersion: f.string('lokVersion'),
        pid: f.int_('pid'),
      ),
      OfficeMessageType.open => OfficeOpen(
        path: f.string('path'),
        readOnly: f.bool_('readOnly'),
        language: f.string('language'),
      ),
      OfficeMessageType.opened => OfficeOpened(
        docType: f.enum_('docType', OfficeDocType.values),
        parts: f.int_('parts'),
        partNames: f.strings('partNames'),
        currentPart: f.int_('currentPart'),
        width: f.int_('width'),
        height: f.int_('height'),
        tileMode: f.enum_('tileMode', OfficePixelFormat.values),
      ),
      OfficeMessageType.passwordNeeded => OfficePasswordNeeded(
        toModify: f.bool_('toModify'),
      ),
      OfficeMessageType.password => OfficePassword(
        password: f.stringOrNull('password'),
      ),
      OfficeMessageType.renderTile => OfficeRenderTile(
        id: f.int_('id'),
        part: f.int_('part'),
        x: f.int_('x'),
        y: f.int_('y'),
        w: f.int_('w'),
        h: f.int_('h'),
        pxW: f.int_('pxW'),
        pxH: f.int_('pxH'),
      ),
      OfficeMessageType.tile => OfficeTile(
        id: f.int_('id'),
        part: f.int_('part'),
        x: f.int_('x'),
        y: f.int_('y'),
        w: f.int_('w'),
        h: f.int_('h'),
        pxW: f.int_('pxW'),
        pxH: f.int_('pxH'),
        format: f.enum_('format', OfficePixelFormat.values),
        pixels: pixels,
      )..checkPixels(),
      OfficeMessageType.key => OfficeKey(
        type: f.enum_('type', OfficeKeyEventType.values),
        charCode: f.int_('charCode'),
        keyCode: f.int_('keyCode'),
      ),
      OfficeMessageType.textInput => OfficeTextInput(
        type: f.enum_('type', OfficeTextInputType.values),
        text: f.string('text'),
      ),
      OfficeMessageType.mouse => OfficeMouse(
        type: f.enum_('type', OfficeMouseEventType.values),
        x: f.int_('x'),
        y: f.int_('y'),
        count: f.int_('count'),
        buttons: f.int_('buttons'),
        modifiers: f.int_('modifiers'),
      ),
      OfficeMessageType.selection => OfficeSelection(
        kind: f.enum_('kind', OfficeSelectionKind.values),
        type: f.int_('type'),
        x: f.int_('x'),
        y: f.int_('y'),
      ),
      OfficeMessageType.uno => OfficeUno(
        id: f.int_('id'),
        command: f.string('command'),
        args: f.string('args'),
      ),
      OfficeMessageType.commandValues => OfficeCommandValues(
        id: f.int_('id'),
        command: f.string('command'),
      ),
      OfficeMessageType.valuesReply => OfficeValues(
        id: f.int_('id'),
        json: f.string('json'),
      ),
      OfficeMessageType.view => OfficeView(
        part: f.int_('part'),
        visibleArea: OfficeRect.fromJson(json['visibleArea'], 'visibleArea'),
        zoom: f.double_('zoom'),
      ),
      OfficeMessageType.setPart => OfficeSetPart(part: f.int_('part')),
      OfficeMessageType.callback => OfficeCallback(
        type: f.string('type'),
        payload: f.string('payload'),
      ),
      OfficeMessageType.save => OfficeSave(
        id: f.int_('id'),
        targetPath: f.string('targetPath'),
        format: f.string('format'),
        filterOptions: f.string('filterOptions'),
      ),
      OfficeMessageType.saved => OfficeSaved(
        id: f.int_('id'),
        ok: f.bool_('ok'),
        error: f.stringOrNull('error'),
      ),
      OfficeMessageType.windowOpened => OfficeWindowOpened(
        windowId: f.int_('windowId'),
        kind: f.string('kind'),
        title: f.string('title'),
        width: f.int_('width'),
        height: f.int_('height'),
        parentId: f.intOrNull('parentId'),
      ),
      OfficeMessageType.windowChanged => OfficeWindowChanged(
        windowId: f.int_('windowId'),
        action: f.string('action'),
        rectangle: json['rectangle'] == null
            ? null
            : OfficeRect.fromJson(json['rectangle'], 'rectangle'),
      ),
      OfficeMessageType.paintWindow => OfficePaintWindow(
        id: f.int_('id'),
        windowId: f.int_('windowId'),
        x: f.int_('x'),
        y: f.int_('y'),
        w: f.int_('w'),
        h: f.int_('h'),
        dpiScale: f.double_('dpiScale'),
      ),
      OfficeMessageType.windowPixels => OfficeWindowPixels(
        id: f.int_('id'),
        windowId: f.int_('windowId'),
        x: f.int_('x'),
        y: f.int_('y'),
        w: f.int_('w'),
        h: f.int_('h'),
        format: f.enum_('format', OfficePixelFormat.values),
        pixels: pixels,
      )..checkPixels(),
      OfficeMessageType.windowMouse => OfficeWindowMouse(
        windowId: f.int_('windowId'),
        type: f.enum_('type', OfficeMouseEventType.values),
        x: f.int_('x'),
        y: f.int_('y'),
        count: f.int_('count'),
        buttons: f.int_('buttons'),
        modifiers: f.int_('modifiers'),
      ),
      OfficeMessageType.windowKey => OfficeWindowKey(
        windowId: f.int_('windowId'),
        type: f.enum_('type', OfficeKeyEventType.values),
        charCode: f.int_('charCode'),
        keyCode: f.int_('keyCode'),
      ),
      OfficeMessageType.windowTextInput => OfficeWindowTextInput(
        windowId: f.int_('windowId'),
        type: f.enum_('type', OfficeTextInputType.values),
        text: f.string('text'),
      ),
      OfficeMessageType.windowClose => OfficeWindowClose(
        windowId: f.int_('windowId'),
      ),
      OfficeMessageType.jsDialog => OfficeJsDialog(json: f.string('json')),
      OfficeMessageType.dialogEvent => OfficeDialogEvent(
        windowId: f.int_('windowId'),
        json: f.string('json'),
      ),
      OfficeMessageType.dialogMode => OfficeDialogModeMessage(
        mode: f.enum_('mode', OfficeDialogMode.values),
      ),
      OfficeMessageType.ping => OfficePing(id: f.int_('id')),
      OfficeMessageType.pong => OfficePong(id: f.int_('id')),
      OfficeMessageType.close => const OfficeClose(),
      OfficeMessageType.closed => const OfficeClosed(),
      OfficeMessageType.error => OfficeError(
        id: f.intOrNull('id'),
        code: f.string('code'),
        message: f.string('message'),
      ),
      OfficeMessageType.copy => OfficeCopy(
        id: f.int_('id'),
        mimeTypes: f.strings('mimeTypes'),
      ),
      OfficeMessageType.clipboard => OfficeClipboard(
        id: f.int_('id'),
        data: f.stringMap('data'),
      ),
      OfficeMessageType.paste => OfficePaste(
        mimeType: f.string('mimeType'),
        data: f.string('data'),
      ),
    };
  }

  @override
  bool operator ==(Object other) {
    if (other is! OfficeMessage || other.messageType != messageType) {
      return false;
    }
    if (jsonEncode(other.toJson()) != jsonEncode(toJson())) return false;
    final a = bytes;
    final b = other.bytes;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(messageType, jsonEncode(toJson()), bytes.length);

  @override
  String toString() =>
      '${messageType.tableName} ${jsonEncode(toJson())}'
      '${bytes.isEmpty ? '' : ' + ${bytes.length} bytes'}';
}

/// A message Forge sends to the helper.
sealed class OfficeHelperCommand extends OfficeMessage {
  const OfficeHelperCommand();
}

/// A message the helper sends to Forge.
sealed class OfficeHelperEvent extends OfficeMessage {
  const OfficeHelperEvent();
}

/// A request that expects a reply carrying the same [id].
abstract interface class OfficeRequest {
  /// The request's id, repeated in its reply.
  int get id;
}

// ---------------------------------------------------------------------------
// Start, open, password

/// helper → Forge: the helper is ready. Forge refuses a [protocol] other than
/// its own ([OfficeProtocolVersionMismatch]).
final class OfficeHello extends OfficeHelperEvent {
  /// See the fields.
  const OfficeHello({
    this.protocol = kOfficeProtocolVersion,
    required this.helperVersion,
    required this.lokVersion,
    required this.pid,
  });

  /// The protocol number the helper speaks.
  final int protocol;

  /// The helper's own version.
  final String helperVersion;

  /// LibreOfficeKit's version JSON (`getVersionInfo`), as text.
  final String lokVersion;

  /// The helper's process id.
  final int pid;

  @override
  OfficeMessageType get messageType => OfficeMessageType.hello;

  @override
  Map<String, Object?> toJson() => {
    'protocol': protocol,
    'helperVersion': helperVersion,
    'lokVersion': lokVersion,
    'pid': pid,
  };
}

/// Forge → helper: open the document at [path].
final class OfficeOpen extends OfficeHelperCommand {
  /// See the fields.
  const OfficeOpen({
    required this.path,
    this.readOnly = false,
    required this.language,
  });

  /// The document's absolute path.
  final String path;

  /// Whether it is opened read-only.
  final bool readOnly;

  /// The language for the load options, e.g. `en-US`.
  final String language;

  @override
  OfficeMessageType get messageType => OfficeMessageType.open;

  @override
  Map<String, Object?> toJson() => {
    'path': path,
    'readOnly': readOnly,
    'language': language,
  };
}

/// helper → Forge: the document is open.
final class OfficeOpened extends OfficeHelperEvent {
  /// See the fields.
  const OfficeOpened({
    required this.docType,
    required this.parts,
    required this.partNames,
    required this.currentPart,
    required this.width,
    required this.height,
    required this.tileMode,
  });

  /// Text, spreadsheet, presentation or drawing.
  final OfficeDocType docType;

  /// The number of parts (sheets, slides, pages of a drawing).
  final int parts;

  /// The parts' names.
  final List<String> partNames;

  /// The part shown.
  final int currentPart;

  /// The current part's width in twips.
  final int width;

  /// The current part's height in twips.
  final int height;

  /// The pixel format of the tiles (`getTileMode`).
  final OfficePixelFormat tileMode;

  @override
  OfficeMessageType get messageType => OfficeMessageType.opened;

  @override
  Map<String, Object?> toJson() => {
    'docType': docType.name,
    'parts': parts,
    'partNames': partNames,
    'currentPart': currentPart,
    'width': width,
    'height': height,
    'tileMode': tileMode.name,
  };
}

/// helper → Forge: the document needs a password, to open it or (with
/// [toModify]) to edit it.
final class OfficePasswordNeeded extends OfficeHelperEvent {
  /// See the fields.
  const OfficePasswordNeeded({required this.toModify});

  /// Whether the password is the one to modify (else the one to open).
  final bool toModify;

  @override
  OfficeMessageType get messageType => OfficeMessageType.passwordNeeded;

  @override
  Map<String, Object?> toJson() => {'toModify': toModify};
}

/// Forge → helper: the password the user gave, or `null` to cancel.
///
/// [toString] never shows the password.
final class OfficePassword extends OfficeHelperCommand {
  /// See the fields.
  const OfficePassword({required this.password});

  /// The password, or `null` when the user cancelled.
  final String? password;

  @override
  OfficeMessageType get messageType => OfficeMessageType.password;

  @override
  Map<String, Object?> toJson() => {'password': password};

  @override
  String toString() =>
      'password ${password == null ? '{cancel}' : '<redacted>'}';
}

// ---------------------------------------------------------------------------
// Tiles

/// Forge → helper: render the area [x], [y], [w], [h] (twips) of [part] into
/// a tile of [pxW] × [pxH] pixels.
final class OfficeRenderTile extends OfficeHelperCommand
    implements OfficeRequest {
  /// See the fields.
  const OfficeRenderTile({
    required this.id,
    required this.part,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.pxW,
    required this.pxH,
  });

  @override
  final int id;

  /// The part rendered.
  final int part;

  /// The area's left edge in twips.
  final int x;

  /// The area's top edge in twips.
  final int y;

  /// The area's width in twips.
  final int w;

  /// The area's height in twips.
  final int h;

  /// The tile's width in pixels.
  final int pxW;

  /// The tile's height in pixels.
  final int pxH;

  @override
  OfficeMessageType get messageType => OfficeMessageType.renderTile;

  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'part': part,
    'x': x,
    'y': y,
    'w': w,
    'h': h,
    'pxW': pxW,
    'pxH': pxH,
  };
}

/// helper → Forge: a rendered tile, the reply to [OfficeRenderTile]. The
/// [pixels] are `pxW × pxH × 4` bytes in [format].
final class OfficeTile extends OfficeHelperEvent {
  /// See the fields.
  OfficeTile({
    required this.id,
    required this.part,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.pxW,
    required this.pxH,
    required this.format,
    required this.pixels,
  });

  /// The id of the [OfficeRenderTile] it answers.
  final int id;

  /// The part rendered.
  final int part;

  /// The area's left edge in twips.
  final int x;

  /// The area's top edge in twips.
  final int y;

  /// The area's width in twips.
  final int w;

  /// The area's height in twips.
  final int h;

  /// The tile's width in pixels.
  final int pxW;

  /// The tile's height in pixels.
  final int pxH;

  /// The pixel format.
  final OfficePixelFormat format;

  /// The pixels, row by row, 4 bytes each.
  final Uint8List pixels;

  @override
  Uint8List get bytes => pixels;

  /// Throws [OfficeProtocolException] when [pixels] is not `pxW × pxH × 4`
  /// bytes long.
  void checkPixels() => _checkPixels(messageType, pxW, pxH, pixels);

  @override
  OfficeMessageType get messageType => OfficeMessageType.tile;

  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'part': part,
    'x': x,
    'y': y,
    'w': w,
    'h': h,
    'pxW': pxW,
    'pxH': pxH,
    'format': format.name,
  };
}

// ---------------------------------------------------------------------------
// Input

/// Forge → helper: a key event (`postKeyEvent`). [keyCode] is a VCL key code
/// with its modifiers added.
final class OfficeKey extends OfficeHelperCommand {
  /// See the fields.
  const OfficeKey({
    required this.type,
    required this.charCode,
    required this.keyCode,
  });

  /// Down (key input) or up.
  final OfficeKeyEventType type;

  /// The character, or 0 for a key without one.
  final int charCode;

  /// The VCL key code with `KEY_SHIFT` / `KEY_MOD1` / `KEY_MOD2` added.
  final int keyCode;

  @override
  OfficeMessageType get messageType => OfficeMessageType.key;

  @override
  Map<String, Object?> toJson() => {
    'type': type.name,
    'charCode': charCode,
    'keyCode': keyCode,
  };
}

/// Forge → helper: text from the input method (`postExtTextInputEvent`):
/// composing text, or the end of the composition.
final class OfficeTextInput extends OfficeHelperCommand {
  /// See the fields.
  const OfficeTextInput({required this.type, required this.text});

  /// Composing (`input`) or ended (`end`).
  final OfficeTextInputType type;

  /// The text.
  final String text;

  @override
  OfficeMessageType get messageType => OfficeMessageType.textInput;

  @override
  Map<String, Object?> toJson() => {'type': type.name, 'text': text};
}

/// Forge → helper: a mouse event in document twips (`postMouseEvent`).
final class OfficeMouse extends OfficeHelperCommand {
  /// See the fields.
  const OfficeMouse({
    required this.type,
    required this.x,
    required this.y,
    this.count = 1,
    this.buttons = 1,
    this.modifiers = 0,
  });

  /// Down, up or move.
  final OfficeMouseEventType type;

  /// The position's x in twips.
  final int x;

  /// The position's y in twips.
  final int y;

  /// The click count: 1, 2 (word) or 3 (paragraph).
  final int count;

  /// LibreOffice's button mask (`MOUSE_LEFT` = 1, …).
  final int buttons;

  /// LibreOffice's modifier mask (`KEY_SHIFT`, `KEY_MOD1`, …).
  final int modifiers;

  @override
  OfficeMessageType get messageType => OfficeMessageType.mouse;

  @override
  Map<String, Object?> toJson() => {
    'type': type.name,
    'x': x,
    'y': y,
    'count': count,
    'buttons': buttons,
    'modifiers': modifiers,
  };
}

/// Forge → helper: a selection handle dragged (`setTextSelection`,
/// `setGraphicSelection`) or the selection reset (`resetSelection`).
final class OfficeSelection extends OfficeHelperCommand {
  /// See the fields.
  const OfficeSelection({
    required this.kind,
    this.type = 0,
    this.x = 0,
    this.y = 0,
  });

  /// Text, graphic, or reset.
  final OfficeSelectionKind kind;

  /// LibreOfficeKit's selection type for the call (`LOK_SETTEXTSELECTION_*`,
  /// `LOK_SETGRAPHICSELECTION_*`).
  final int type;

  /// The handle's x in twips.
  final int x;

  /// The handle's y in twips.
  final int y;

  @override
  OfficeMessageType get messageType => OfficeMessageType.selection;

  @override
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'type': type,
    'x': x,
    'y': y,
  };
}

/// Forge → helper: copy the selection (`getTextSelection`) in each of
/// [mimeTypes]; answered by [OfficeClipboard].
final class OfficeCopy extends OfficeHelperCommand implements OfficeRequest {
  /// See the fields.
  const OfficeCopy({
    required this.id,
    this.mimeTypes = const ['text/plain;charset=utf-8', 'text/html'],
  });

  @override
  final int id;

  /// The MIME types asked for, in order of preference.
  final List<String> mimeTypes;

  @override
  OfficeMessageType get messageType => OfficeMessageType.copy;

  @override
  Map<String, Object?> toJson() => {'id': id, 'mimeTypes': mimeTypes};
}

/// helper → Forge: the selection as each MIME type the helper could give,
/// the reply to [OfficeCopy].
final class OfficeClipboard extends OfficeHelperEvent {
  /// See the fields.
  const OfficeClipboard({required this.id, required this.data});

  /// The id of the [OfficeCopy] it answers.
  final int id;

  /// MIME type → the selection in it.
  final Map<String, String> data;

  @override
  OfficeMessageType get messageType => OfficeMessageType.clipboard;

  @override
  Map<String, Object?> toJson() => {'id': id, 'data': data};
}

/// Forge → helper: paste [data] of [mimeType] (LibreOfficeKit's `paste`).
final class OfficePaste extends OfficeHelperCommand {
  /// See the fields.
  const OfficePaste({required this.mimeType, required this.data});

  /// The data's MIME type, e.g. `text/html` or `text/plain;charset=utf-8`.
  final String mimeType;

  /// The data.
  final String data;

  @override
  OfficeMessageType get messageType => OfficeMessageType.paste;

  @override
  Map<String, Object?> toJson() => {'mimeType': mimeType, 'data': data};
}

// ---------------------------------------------------------------------------
// Commands, view, callbacks

/// Forge → helper: a UNO command (`postUnoCommand`), e.g. `.uno:Bold`, with
/// its arguments as JSON text; its `UNO_COMMAND_RESULT` comes back as a
/// [OfficeCallback].
final class OfficeUno extends OfficeHelperCommand implements OfficeRequest {
  /// See the fields.
  const OfficeUno({required this.id, required this.command, this.args = ''});

  @override
  final int id;

  /// The command, `.uno:<Name>`.
  final String command;

  /// Its arguments as JSON text, empty for none.
  final String args;

  @override
  OfficeMessageType get messageType => OfficeMessageType.uno;

  @override
  Map<String, Object?> toJson() => {'id': id, 'command': command, 'args': args};
}

/// Forge → helper: the values of [command] (`getCommandValues`), e.g.
/// `.uno:StyleApply`; answered by [OfficeValues].
final class OfficeCommandValues extends OfficeHelperCommand
    implements OfficeRequest {
  /// See the fields.
  const OfficeCommandValues({required this.id, required this.command});

  @override
  final int id;

  /// The command whose values are asked for.
  final String command;

  @override
  OfficeMessageType get messageType => OfficeMessageType.commandValues;

  @override
  Map<String, Object?> toJson() => {'id': id, 'command': command};
}

/// helper → Forge: the values asked for by [OfficeCommandValues], as JSON
/// text.
final class OfficeValues extends OfficeHelperEvent {
  /// See the fields.
  const OfficeValues({required this.id, required this.json});

  /// The id of the [OfficeCommandValues] it answers.
  final int id;

  /// `getCommandValues`' JSON text.
  final String json;

  @override
  OfficeMessageType get messageType => OfficeMessageType.valuesReply;

  @override
  Map<String, Object?> toJson() => {'id': id, 'json': json};
}

/// Forge → helper: what the editor shows (`setClientVisibleArea`,
/// `setClientZoom`).
final class OfficeView extends OfficeHelperCommand {
  /// See the fields.
  const OfficeView({
    required this.part,
    required this.visibleArea,
    required this.zoom,
  });

  /// The part shown.
  final int part;

  /// The visible area in twips.
  final OfficeRect visibleArea;

  /// Tile pixels per twip.
  final double zoom;

  @override
  OfficeMessageType get messageType => OfficeMessageType.view;

  @override
  Map<String, Object?> toJson() => {
    'part': part,
    'visibleArea': visibleArea.toJson(),
    'zoom': zoom,
  };
}

/// Forge → helper: switch to [part] (`setPart`).
final class OfficeSetPart extends OfficeHelperCommand {
  /// See the fields.
  const OfficeSetPart({required this.part});

  /// The part, from 0.
  final int part;

  @override
  OfficeMessageType get messageType => OfficeMessageType.setPart;

  @override
  Map<String, Object?> toJson() => {'part': part};
}

/// helper → Forge: a LibreOfficeKit callback, forwarded uninterpreted.
final class OfficeCallback extends OfficeHelperEvent {
  /// See the fields.
  const OfficeCallback({required this.type, required this.payload});

  /// The callback's `LOK_CALLBACK_*` name without the prefix, e.g.
  /// `INVALIDATE_TILES`.
  final String type;

  /// The payload as LibreOfficeKit gave it.
  final String payload;

  @override
  OfficeMessageType get messageType => OfficeMessageType.callback;

  @override
  Map<String, Object?> toJson() => {'type': type, 'payload': payload};
}

// ---------------------------------------------------------------------------
// Saving

/// Forge → helper: save the document to [targetPath] (a temporary file
/// beside the original) in [format] (empty: its own format).
final class OfficeSave extends OfficeHelperCommand implements OfficeRequest {
  /// See the fields.
  const OfficeSave({
    required this.id,
    required this.targetPath,
    this.format = '',
    this.filterOptions = '',
  });

  @override
  final int id;

  /// Where the helper writes.
  final String targetPath;

  /// The format (`docx`, `odt`, `pdf`, …), empty for the document's own.
  final String format;

  /// The filter options passed to `saveAs`.
  final String filterOptions;

  @override
  OfficeMessageType get messageType => OfficeMessageType.save;

  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'targetPath': targetPath,
    'format': format,
    'filterOptions': filterOptions,
  };
}

/// helper → Forge: how [OfficeSave] went.
final class OfficeSaved extends OfficeHelperEvent {
  /// See the fields.
  const OfficeSaved({required this.id, required this.ok, this.error});

  /// The id of the [OfficeSave] it answers.
  final int id;

  /// Whether the target was written.
  final bool ok;

  /// Why not, when [ok] is false.
  final String? error;

  @override
  OfficeMessageType get messageType => OfficeMessageType.saved;

  @override
  Map<String, Object?> toJson() => {'id': id, 'ok': ok, 'error': error};
}

// ---------------------------------------------------------------------------
// Dialogs as windows

/// helper → Forge: LibreOffice opened a window (the `WINDOW` callback's
/// `created` action).
final class OfficeWindowOpened extends OfficeHelperEvent {
  /// See the fields.
  const OfficeWindowOpened({
    required this.windowId,
    required this.kind,
    required this.title,
    required this.width,
    required this.height,
    this.parentId,
  });

  /// The window's id.
  final int windowId;

  /// `dialog`, `child`, `tooltip`, … as LibreOffice names it.
  final String kind;

  /// Its title.
  final String title;

  /// Its width in pixels.
  final int width;

  /// Its height in pixels.
  final int height;

  /// The window it belongs to, if any.
  final int? parentId;

  @override
  OfficeMessageType get messageType => OfficeMessageType.windowOpened;

  @override
  Map<String, Object?> toJson() => {
    'windowId': windowId,
    'kind': kind,
    'title': title,
    'width': width,
    'height': height,
    'parentId': parentId,
  };
}

/// helper → Forge: a window changed (`invalidate`, `size_changed`,
/// `cursor_invalidate`, `title_changed`, `close`, as LibreOffice names it).
final class OfficeWindowChanged extends OfficeHelperEvent {
  /// See the fields.
  const OfficeWindowChanged({
    required this.windowId,
    required this.action,
    this.rectangle,
  });

  /// The window's id.
  final int windowId;

  /// The `WINDOW` callback's action.
  final String action;

  /// The area concerned, in pixels, when the action names one.
  final OfficeRect? rectangle;

  @override
  OfficeMessageType get messageType => OfficeMessageType.windowChanged;

  @override
  Map<String, Object?> toJson() => {
    'windowId': windowId,
    'action': action,
    'rectangle': rectangle?.toJson(),
  };
}

/// Forge → helper: paint an area of a window (`paintWindow`); answered by
/// [OfficeWindowPixels].
final class OfficePaintWindow extends OfficeHelperCommand
    implements OfficeRequest {
  /// See the fields.
  const OfficePaintWindow({
    required this.id,
    required this.windowId,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.dpiScale = 1.0,
  });

  @override
  final int id;

  /// The window's id.
  final int windowId;

  /// The area's left edge in pixels.
  final int x;

  /// The area's top edge in pixels.
  final int y;

  /// The area's width in pixels.
  final int w;

  /// The area's height in pixels.
  final int h;

  /// The device pixel ratio to paint at.
  final double dpiScale;

  @override
  OfficeMessageType get messageType => OfficeMessageType.paintWindow;

  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'windowId': windowId,
    'x': x,
    'y': y,
    'w': w,
    'h': h,
    'dpiScale': dpiScale,
  };
}

/// helper → Forge: a window's pixels, the reply to [OfficePaintWindow]. The
/// [pixels] are `w × h × 4` bytes in [format].
final class OfficeWindowPixels extends OfficeHelperEvent {
  /// See the fields.
  OfficeWindowPixels({
    required this.id,
    required this.windowId,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.format,
    required this.pixels,
  });

  /// The id of the [OfficePaintWindow] it answers.
  final int id;

  /// The window's id.
  final int windowId;

  /// The area's left edge in pixels.
  final int x;

  /// The area's top edge in pixels.
  final int y;

  /// The width of [pixels] in pixels.
  final int w;

  /// The height of [pixels] in pixels.
  final int h;

  /// The pixel format.
  final OfficePixelFormat format;

  /// The pixels, row by row, 4 bytes each.
  final Uint8List pixels;

  @override
  Uint8List get bytes => pixels;

  /// Throws [OfficeProtocolException] when [pixels] is not `w × h × 4` bytes
  /// long.
  void checkPixels() => _checkPixels(messageType, w, h, pixels);

  @override
  OfficeMessageType get messageType => OfficeMessageType.windowPixels;

  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'windowId': windowId,
    'x': x,
    'y': y,
    'w': w,
    'h': h,
    'format': format.name,
  };
}

/// Forge → helper: a mouse event in a window, in its pixels
/// (`postWindowMouseEvent`).
final class OfficeWindowMouse extends OfficeHelperCommand {
  /// See the fields.
  const OfficeWindowMouse({
    required this.windowId,
    required this.type,
    required this.x,
    required this.y,
    this.count = 1,
    this.buttons = 1,
    this.modifiers = 0,
  });

  /// The window's id.
  final int windowId;

  /// Down, up or move.
  final OfficeMouseEventType type;

  /// The position's x in pixels.
  final int x;

  /// The position's y in pixels.
  final int y;

  /// The click count.
  final int count;

  /// LibreOffice's button mask.
  final int buttons;

  /// LibreOffice's modifier mask.
  final int modifiers;

  @override
  OfficeMessageType get messageType => OfficeMessageType.windowMouse;

  @override
  Map<String, Object?> toJson() => {
    'windowId': windowId,
    'type': type.name,
    'x': x,
    'y': y,
    'count': count,
    'buttons': buttons,
    'modifiers': modifiers,
  };
}

/// Forge → helper: a key event in a window (`postWindowKeyEvent`).
final class OfficeWindowKey extends OfficeHelperCommand {
  /// See the fields.
  const OfficeWindowKey({
    required this.windowId,
    required this.type,
    required this.charCode,
    required this.keyCode,
  });

  /// The window's id.
  final int windowId;

  /// Down (key input) or up.
  final OfficeKeyEventType type;

  /// The character, or 0.
  final int charCode;

  /// The VCL key code with its modifiers.
  final int keyCode;

  @override
  OfficeMessageType get messageType => OfficeMessageType.windowKey;

  @override
  Map<String, Object?> toJson() => {
    'windowId': windowId,
    'type': type.name,
    'charCode': charCode,
    'keyCode': keyCode,
  };
}

/// Forge → helper: input-method text in a window
/// (`postWindowExtTextInputEvent`).
final class OfficeWindowTextInput extends OfficeHelperCommand {
  /// See the fields.
  const OfficeWindowTextInput({
    required this.windowId,
    required this.type,
    required this.text,
  });

  /// The window's id.
  final int windowId;

  /// Composing or ended.
  final OfficeTextInputType type;

  /// The text.
  final String text;

  @override
  OfficeMessageType get messageType => OfficeMessageType.windowTextInput;

  @override
  Map<String, Object?> toJson() => {
    'windowId': windowId,
    'type': type.name,
    'text': text,
  };
}

/// Forge → helper: close a window (the user closed its overlay).
final class OfficeWindowClose extends OfficeHelperCommand {
  /// See the fields.
  const OfficeWindowClose({required this.windowId});

  /// The window's id.
  final int windowId;

  @override
  OfficeMessageType get messageType => OfficeMessageType.windowClose;

  @override
  Map<String, Object?> toJson() => {'windowId': windowId};
}

// ---------------------------------------------------------------------------
// Dialogs as JSON

/// helper → Forge: a `JSDIALOG` payload: a dialog's widget tree, or an update
/// or action for a widget of an open one, as JSON text.
///
/// The desktop LibreOffice of the first spike sends none; the message stays
/// for a LibreOffice that has JSON dialogs.
final class OfficeJsDialog extends OfficeHelperEvent {
  /// See the fields.
  const OfficeJsDialog({required this.json});

  /// The payload.
  final String json;

  @override
  OfficeMessageType get messageType => OfficeMessageType.jsDialog;

  @override
  Map<String, Object?> toJson() => {'json': json};
}

/// Forge → helper: a widget event of a JSON dialog, passed to
/// `sendDialogEvent`.
final class OfficeDialogEvent extends OfficeHelperCommand {
  /// See the fields.
  const OfficeDialogEvent({required this.windowId, required this.json});

  /// The dialog's window id.
  final int windowId;

  /// The widget id, the event type and its data, as JSON text.
  final String json;

  @override
  OfficeMessageType get messageType => OfficeMessageType.dialogEvent;

  @override
  Map<String, Object?> toJson() => {'windowId': windowId, 'json': json};
}

/// Forge → helper: how dialogs opened from now on are shown (`dialogMode`).
final class OfficeDialogModeMessage extends OfficeHelperCommand {
  /// See the fields.
  const OfficeDialogModeMessage({required this.mode});

  /// Windows or JSON.
  final OfficeDialogMode mode;

  @override
  OfficeMessageType get messageType => OfficeMessageType.dialogMode;

  @override
  Map<String, Object?> toJson() => {'mode': mode.name};
}

// ---------------------------------------------------------------------------
// Liveness, shutdown, errors

/// Forge → helper: are you alive? Answered by [OfficePong].
final class OfficePing extends OfficeHelperCommand implements OfficeRequest {
  /// See the fields.
  const OfficePing({required this.id});

  @override
  final int id;

  @override
  OfficeMessageType get messageType => OfficeMessageType.ping;

  @override
  Map<String, Object?> toJson() => {'id': id};
}

/// helper → Forge: the reply to [OfficePing].
final class OfficePong extends OfficeHelperEvent {
  /// See the fields.
  const OfficePong({required this.id});

  /// The id of the [OfficePing] it answers.
  final int id;

  @override
  OfficeMessageType get messageType => OfficeMessageType.pong;

  @override
  Map<String, Object?> toJson() => {'id': id};
}

/// Forge → helper: close the document and exit.
final class OfficeClose extends OfficeHelperCommand {
  /// The message.
  const OfficeClose();

  @override
  OfficeMessageType get messageType => OfficeMessageType.close;

  @override
  Map<String, Object?> toJson() => const {};
}

/// helper → Forge: the document and the office are closed; the helper exits.
final class OfficeClosed extends OfficeHelperEvent {
  /// The message.
  const OfficeClosed();

  @override
  OfficeMessageType get messageType => OfficeMessageType.closed;

  @override
  Map<String, Object?> toJson() => const {};
}

/// helper → Forge: something failed, tied to the request [id] when there is
/// one.
final class OfficeError extends OfficeHelperEvent {
  /// See the fields.
  const OfficeError({this.id, required this.code, required this.message});

  /// The request it answers, or `null`.
  final int? id;

  /// A short machine-readable code, e.g. `loadFailed`.
  final String code;

  /// The text for the user and the trail.
  final String message;

  @override
  OfficeMessageType get messageType => OfficeMessageType.error;

  @override
  Map<String, Object?> toJson() => {'id': id, 'code': code, 'message': message};
}

// ---------------------------------------------------------------------------
// Reading fields

void _checkPixels(OfficeMessageType type, int w, int h, Uint8List pixels) {
  if (w < 0 || h < 0 || pixels.length != w * h * 4) {
    throw OfficeProtocolException(
      OfficeProtocolErrorCode.malformed,
      '${type.tableName}: $w × $h pixels need ${w * h * 4} bytes, '
      'got ${pixels.length}',
    );
  }
}

Map<String, Object?> _asMap(Object? value, String field) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  throw OfficeProtocolException(
    OfficeProtocolErrorCode.malformed,
    '$field: expected an object, got ${value.runtimeType}',
  );
}

/// The fields of one message's header, read strictly.
final class _Fields {
  _Fields(this.json, this.message);

  final Map<String, Object?> json;
  final String message;

  Never _wrong(String field, String expected) => throw OfficeProtocolException(
    OfficeProtocolErrorCode.malformed,
    '$message.$field: expected $expected, got '
    '${json.containsKey(field) ? json[field].runtimeType : 'nothing'}',
  );

  int int_(String field) {
    final v = json[field];
    if (v is int) return v;
    _wrong(field, 'an integer');
  }

  int? intOrNull(String field) {
    final v = json[field];
    if (v == null || v is int) return v as int?;
    _wrong(field, 'an integer or null');
  }

  double double_(String field) {
    final v = json[field];
    if (v is num) return v.toDouble();
    _wrong(field, 'a number');
  }

  bool bool_(String field) {
    final v = json[field];
    if (v is bool) return v;
    _wrong(field, 'a boolean');
  }

  String string(String field) {
    final v = json[field];
    if (v is String) return v;
    _wrong(field, 'a string');
  }

  String? stringOrNull(String field) {
    final v = json[field];
    if (v == null || v is String) return v as String?;
    _wrong(field, 'a string or null');
  }

  List<String> strings(String field) {
    final v = json[field];
    if (v is List && v.every((e) => e is String)) {
      return List.unmodifiable(v.cast<String>());
    }
    _wrong(field, 'a list of strings');
  }

  Map<String, String> stringMap(String field) {
    final v = json[field];
    if (v is Map && v.values.every((e) => e is String)) {
      return Map.unmodifiable(v.cast<String, String>());
    }
    _wrong(field, 'an object of strings');
  }

  T enum_<T extends Enum>(String field, List<T> values) {
    final v = json[field];
    for (final e in values) {
      if (e.name == v) return e;
    }
    _wrong(field, 'one of ${values.map((e) => e.name).join(', ')}');
  }
}

// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The office editor: [TomOfficeEditor], a widget that shows and edits an
/// office document served by the LibreOfficeKit helper (`tom_office_host`)
/// over protocol 1; its [TomOfficeEditorController]; the
/// [TomOfficeEditorHost] an application implements; the tile cache. No
/// `dart:io`: detection and the process launcher are in `io.dart`, a fake
/// helper in `testing.dart`.
library;

export 'package:tom_office_protocol/tom_office_protocol.dart'
    show
        OfficeDocType,
        OfficeMouseEventType,
        OfficePixelFormat,
        OfficeSelectionKind;

export 'src/callbacks.dart';
export 'src/controller.dart';
export 'src/detection/installation.dart';
export 'src/helper/helper_channel.dart';
export 'src/host.dart';
export 'src/input/vcl_keys.dart';
export 'src/ribbon/ribbon.dart';
export 'src/ribbon/ribbon_model.dart';
export 'src/office_editor_trail.dart'
    show kOfficeEditorDebug, officeTrail, officeReport;
export 'src/tiles/tile_cache.dart';
export 'src/widgets/dialog_layer.dart';
export 'src/widgets/document_view.dart';
export 'src/widgets/office_editor.dart';
export 'src/widgets/panels.dart';

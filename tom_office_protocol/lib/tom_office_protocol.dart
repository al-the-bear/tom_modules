/// Protocol 1 between the office editor and its LibreOfficeKit helper
/// process `tom_office_host`: the sealed message classes
/// ([OfficeHelperCommand] from Forge, [OfficeHelperEvent] from the helper),
/// the frame codec ([OfficeProtocolCodec], [OfficeFrameReader]) and the
/// protocol number [kOfficeProtocolVersion].
///
/// Pure Dart: no Flutter and no `dart:io`, so both the Flutter editor and the
/// command-line helper import it.
library;

export 'src/codec.dart';
export 'src/errors.dart';
export 'src/messages.dart';

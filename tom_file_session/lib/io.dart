/// The `dart:io` part of `tom_file_session`, for hosts that run on a desktop
/// or a server: [TomBinaryFileAccess], the save rules for files an editor
/// does not hold as text (office documents, PDFs), and
/// [TomLocalContentServer], the local HTTP server that hands content to a
/// webview and takes the saved bytes back.
///
/// The main library `tom_file_session.dart` stays free of `dart:io`, so a
/// browser build links it; import this one beside it where `dart:io` is
/// available.
library;

export 'src/binary_files.dart';
export 'src/io/binary_file_access.dart';
export 'src/io/local_content_server.dart';

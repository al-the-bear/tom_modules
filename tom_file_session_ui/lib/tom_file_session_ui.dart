/// The binding of an editor to a `tom_file_session` session
/// ([ForgeSessionFile]) and the frame that shows the file's state above the
/// editor ([ForgeSessionFileFrame]).
///
/// One implementation for every editor that edits a file through a session:
/// `tom_file_editors` re-exports it, Tom Forge's kit re-exports the binding
/// and `tom_forge_shared_ui` the frame.
library;

export 'src/forge_session_file.dart';

/// What an editor and a file browser build on the file-system contract of
/// `tom_file_system`: [ForgeFileSession], the editing session of one file;
/// [ForgeFilter] with [ForgeBuiltInPresets], what a file tree shows; and
/// [ForgeEnvFile], the `.env` codec.
///
/// Reaches no `dart:io` and no Flutter, so a browser build links it.
library;

export 'src/env_file.dart';
export 'src/file_session.dart';
export 'src/filter.dart';

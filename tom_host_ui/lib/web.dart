/// Browser host capabilities: both clipboard flavours in one `ClipboardItem`,
/// and printing through a hidden iframe. Off the web (a VM test) both answer
/// "this process could not".
library;

export 'src/clipboard/browser_clipboard.dart';
export 'src/print/browser_print.dart';
export 'tom_host_ui.dart';

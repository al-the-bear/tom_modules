/// The off-web half of `browser_print.dart`'s conditional import: on the VM
/// there is no print dialog to open.
library;

Future<String?> printHtmlInBrowserImpl(String jobTitle, String html) async =>
    null;

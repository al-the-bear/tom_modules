/// The off-web half of `browser_clipboard.dart`'s conditional import.
///
/// Reached only where there is no browser (a `flutter test` on the VM). "This
/// process could not" is the accurate answer, and it is the same value the
/// browser half returns when the user or the platform refuses.
library;

Future<bool> placeBothFlavoursImpl({
  required String html,
  required String text,
}) async => false;

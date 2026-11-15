/// The one function shape a host's print path has.
library;

/// Hands one finished, self-contained HTML document to the platform's print
/// pipeline, returning a short description of where the job went, or null
/// when nothing was printed.
///
/// The host receives **HTML and not a job description**: there is one
/// rendering, and the platform lays it out. It is also where a PDF comes from
/// — every desktop and browser print dialog offers "save as PDF", so a second
/// Dart-side PDF writer would be a second layout engine for a format the
/// platform already renders from the first.
typedef TomPrintHtml = Future<String?> Function(String jobTitle, String html);

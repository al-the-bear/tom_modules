# Tom Modules

Reusable components of the Tom workspace on a business level: shared models
and the code that reads, writes, serialises and changes them. They are not of
general interest the way `tom_basics` or `tom_core` are, but several Tom
applications use the same model, so it lives here once.

| Package | What it is |
| --- | --- |
| [`tom_todo_model`](tom_todo_model/) | The shared todo model (`TomTodo`) and the `*.todo.yaml` file codec. |
| [`tom_calendar_model`](tom_calendar_model/) | The calendar model: appointments timed in UTC or all-day, a recurrence subset with on-demand expansion, occurrence and series edits, display time frames, tasks, and an RFC 5545 codec. |
| [`tom_formula`](tom_formula/) | A spreadsheet formula engine: the grammar and printer, the function library, dependency-tracked recalculation, lowering to Dart, and the backend port, with a conformance corpus in `testing.dart`. |
| [`tom_file_session`](tom_file_session/) | The editing session of one file over `tom_file_system` (encoding, byte preservation, explicit save, external changes, undo), the file-tree filter with its presets, and the `.env` codec; for `dart:io` hosts, binary saves and the local content server for webviews (`io.dart`). |
| [`tom_office_protocol`](tom_office_protocol/) | Protocol 1 between the office editor and its LibreOfficeKit helper: the message types, the frame codec of the stdio transport, the protocol number. Not published. |
| [`tom_office_host`](tom_office_host/) | The LibreOfficeKit helper process of the office editors: one document per process, protocol 1 on stdin and stdout. Not published. |

The Tom UI modules — Flutter widgets and host capabilities that several Tom
applications share, each package one purpose:

| Package | What it is |
| --- | --- |
| [`tom_ui_support`](tom_ui_support/) | Colours kept readable (WCAG AA), the editing-surface marker, the notice queue, running a change after the frame. |
| [`tom_ui_controls`](tom_ui_controls/) | The tree view with its controller and theme, split panels with draggable separators, the search and replace box, small action buttons and collapse toggles, validation markers with their error model. |
| [`tom_ui_testing`](tom_ui_testing/) | Test support: the golden harness (real fonts, content, contrast and machine-path checks) and `tester.pumpUntil`. |
| [`tom_host_ui`](tom_host_ui/) | Copy with formatting, the protected-value clipboard binding, printing HTML through the platform's dialog; desktop and browser. |
| [`tom_credentials_ui`](tom_credentials_ui/) | Key and token prompts, the sign-in item, the platform keychain as a secret store. |
| [`tom_sync_ui`](tom_sync_ui/) | The sync status and its indicator, the three-way merge view. |
| [`tom_calendar_ui`](tom_calendar_ui/) | Date, time and repeat fields over `tom_calendar_model`, the appointment editor. |
| [`tom_text_highlight`](tom_text_highlight/) | The one syntax-highlighting interface (`SyntaxHighlighter`, `HighlightSpan`), token themes, and light highlighters for YAML, Markdown, JSON, shell and `.env`; Flutter only. |
| [`tom_file_editors`](tom_file_editors/) | Byte-preserving file editors over `tom_file_session` (text, `.env`, YAML and Markdown highlighting), the schema cache, the Markdown renderer. |
| [`tom_mermaid_view`](tom_mermaid_view/) | Mermaid diagrams in a webview with the bundled mermaid.js (11.13.0, MIT); the webview is the Tom fork, taken by path. Not published. |
| [`tom_pdf_editor`](tom_pdf_editor/) | The PDF editor without an engine: scroll, zoom, page list, search, selection and copy, links, annotations and forms over the engine interface; the controller and host interface. Not published. |
| [`tom_pdf_pdfium`](tom_pdf_pdfium/) | The PDF editor's PDFium engine (FFI on an engine isolate) and the PDFium locator. Not published. |
| [`tom_pdf_pdfjs`](tom_pdf_pdfjs/) | The pdf.js view in the Tom webview fork, with pdf.js 6.5.438 vendored. Not published. |
| [`tom_office_editor`](tom_office_editor/) | The office editor over the installed LibreOffice (LibreOfficeKit in the helper `tom_office_host`, protocol 1): tiles, input, the ribbon, LibreOffice's dialogs, the controller and host interface, detection and the helper launcher. Not published. |
| [`tom_office_zetaoffice`](tom_office_zetaoffice/) | The office editor's ZetaOffice route (LibreOffice compiled to WebAssembly) in the Tom webview fork, on the office editor's host; ZetaOffice downloaded once and cached. Not published. |
| [`tom_todo_ui`](tom_todo_ui/) | The todo row, badges and details editor, and the `*.todo.yaml` file editor. |
| [`tom_agentic_ui`](tom_agentic_ui/) | The agent and chat UI over `tom_core_agentic`: the composer with its placeholder preview, the send controller and reconnect banner, the prompt queue and trail, the agent connection picker, the change log and its review. |
| [`tom_ai_trail_ui`](tom_ai_trail_ui/) | The live trails of AI sessions over `tom_llm`, as a panel, a chip or a phone sheet. |
| [`tom_media_probe`](tom_media_probe/) | Probe application of the planned audio and video libraries (recording, extraction, transcript, analysis) on six platforms, with its extraction plugin `tom_media_extract_probe` in `extract/`. Not a library; not published. |

Each package has its own README and changelog, and each is published on
pub.dev except those marked *Not published*; inside the workspace they are
taken by path.

## License

BSD 3-Clause. See [LICENSE](LICENSE).

## Disclaimer

This software is provided "as is", without warranty of any kind, express or
implied, including but not limited to the warranties of merchantability and
fitness for a particular purpose. In no event shall the authors, copyright
holders or contributors be liable for any claim, damages or other liability
arising from, out of or in connection with the software or its use. This
section summarises the warranty and liability disclaimer of the licence;
the licence text in [LICENSE](LICENSE) governs.

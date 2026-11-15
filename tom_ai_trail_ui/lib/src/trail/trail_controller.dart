/// The AI trail panel's state — which session is shown, what the filter
/// hides, whether the panel is open and how tall it is.
///
/// The trails themselves are the session manager's (`LlmTrails` of
/// `tom_llm`), which the application's composition root hands in, so the
/// view names no AI implementation. A root with no AI transport hands in
/// none, and then there is no panel at all — [isAvailable] is false.
///
/// The panel's open state and height, and whether a starting run opens it,
/// are the host's device state: the host binds the writers, and [adopt] takes
/// what was read without writing it back.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:tom_llm/tom_llm.dart';

import 'package:tom_ui_support/tom_ui_support.dart';
import 'docked_run.dart';

/// Where a session's trail file is written, as the panel header says it
///. Supplied by the root, which owns the trail files.
class TomAiTrailFileStatus {
  /// The trail file — written, or for a memory-only session the one that
  /// would be written once persistence is turned on.
  final String path;

  /// Whether the session's trail is kept in memory only.
  final bool memoryOnly;

  /// Why: the rule that chose the directory ("set in settings", …), or
  /// for a memory-only session, why it is kept in memory.
  final String reason;

  /// Turns persistence on for a memory-only session, after the
  /// view has warned and the user confirmed. Null where it cannot be offered.
  final Future<void> Function()? keepOnDisk;

  const TomAiTrailFileStatus({
    required this.path,
    required this.reason,
    this.memoryOnly = false,
    this.keepOnDisk,
  });
}

/// Where the trail files go on this device, as the Settings row says
/// it.
class TomAiTrailDirectoryInfo {
  /// The directory the files are written to.
  final String path;

  /// The rule that chose it ("set in settings", …).
  final String reason;

  /// The directory this device's setting names, or null when it names none
  /// and a later rule decides.
  final String? setting;

  const TomAiTrailDirectoryInfo({
    required this.path,
    required this.reason,
    this.setting,
  });
}

/// How the trail view shows a notice — a copy confirmed, a session that could
/// not be created or removed. [kind] names the notice for a host that queues
/// or replaces notices by kind.
typedef TomAiTrailNotice =
    void Function(
      BuildContext context, {
      required String kind,
      required String message,
    });

/// The trail panel's state.
class TomAiTrailController extends ChangeNotifier {
  /// The default height of the panel, in logical pixels.
  @visibleForTesting
  static const double defaultHeight = 260;

  /// The smallest height the splitter allows.
  static const double minHeight = 96;

  TomAiTrailController({this.trails, LlmSessionRegistry? registry})
      : registry = registry ?? LlmSessionRegistry() {
    final source = trails;
    if (source != null) {
      _records = source.records.listen(_onRecord);
      _changes = source.changes.listen((_) => _changed());
    }
    _registryChanges = this.registry.changes.listen((_) => _changed());
  }

  /// The sessions: the two built-ins and those the user created, and which
  /// one an AI gesture runs in.
  final LlmSessionRegistry registry;

  StreamSubscription<void>? _registryChanges;

  /// The quest folders a quest session can be bound to: every
  /// quest-shaped folder under a registered Workspace root. Bound by a root
  /// that has a Workspace area; null where there is none, and then only
  /// internal sessions can be created.
  Future<List<String>> Function()? questFolders;

  /// The host's notice surface for the view's notices; a plain snack bar when
  /// unbound.
  TomAiTrailNotice? showNotice;

  /// Creates a session named [name] — a quest session when [questFolder] is
  /// given — and shows its tab.
  Future<LlmSessionInfo> createSession(
    String name, {
    String? questFolder,
  }) async {
    final session = await registry.create(name, questFolder: questFolder);
    select(session.id);
    return session;
  }

  /// Gives the user's session [id] the label [name].
  Future<void> renameSession(String id, String name) =>
      registry.rename(id, name);

  /// Removes the user's session [id] and its tab. Refused while it has a run.
  /// The files it wrote stay where they are.
  Future<void> removeSession(String id) async {
    if (_isBusy(id)) {
      throw const LlmSessionException(
          'A session cannot be removed while it has a run.');
    }
    await registry.remove(id);
    closeSession(id);
  }

  /// The label of session [id]: its name, or the id for a session the
  /// registry does not know.
  String sessionName(String id) => registry.byId(id)?.name ?? id;

  /// The trails shown, or null on a root with no AI transport.
  final LlmTrails? trails;

  StreamSubscription<LlmTrailRecord>? _records;
  StreamSubscription<String>? _changes;

  /// Whether this build has a trail panel: it has trails, or a run started
  /// from the shell is docked in one (a build with a provider and no trail
  /// manager still shows its runs somewhere).
  bool get isAvailable => trails != null || _docked.isNotEmpty;

  /// The runs started from the application, by the session they run in (one at a
  /// time per session, any number of sessions at once).
  final Map<String, TomDockedAiRun> _docked = {};

  /// The run docked in [sessionId]'s tab, or null.
  TomDockedAiRun? dockedRun(String sessionId) => _docked[sessionId];

  /// Every docked run, in the order their sessions' tabs show.
  List<TomDockedAiRun> get dockedRuns => [
        for (final id in sessions) ?_docked[id],
      ];

  /// Whether [sessionId] cannot take another run now: a run is streaming in
  /// it, or one docked there is still being set up or decided.
  bool _isBusy(String sessionId) =>
      isRunning(sessionId) || (_docked[sessionId]?.isActive ?? false);

  /// Docks [run] in its session's tab, shows that tab and opens the panel.
  ///
  /// Refused while the session is busy: a session runs one run at a time, and the refusal names the way out — another session. A run
  /// that has ended in that tab is replaced.
  void dock(TomDockedAiRun run) {
    final id = run.sessionId;
    if (_isBusy(id)) {
      throw LlmSessionException(
          'The session "${sessionName(id)}" already has a run. Wait for it, '
          'or choose another session for this action from the session '
          'menu.');
    }
    _release(id);
    _docked[id] = run;
    run.addListener(_changed);
    select(id);
    unawaited(setOpen(true));
    _changed();
  }

  /// Moves [run], not yet started, to [sessionId] and shows that tab — the
  /// agent run's session picker. Refused when that session is busy.
  void moveDocked(TomDockedAiRun run, String sessionId) {
    if (run.sessionId == sessionId) return;
    if (_isBusy(sessionId)) {
      throw LlmSessionException(
          'The session "${sessionName(sessionId)}" already has a run.');
    }
    if (_docked[run.sessionId] == run) _docked.remove(run.sessionId);
    _release(sessionId);
    run.retarget(sessionId);
    _docked[sessionId] = run;
    select(sessionId);
    _changed();
  }

  /// Discards the run docked in [sessionId], if any: a request still
  /// streaming is cancelled and a proposal is rejected.
  void undock(String sessionId) {
    _release(sessionId);
    _changed();
  }

  void _release(String sessionId) {
    final run = _docked.remove(sessionId);
    if (run == null) return;
    run.removeListener(_changed);
    run.discard();
    run.dispose();
  }

  /// Writes `aiTrailPanel`, answering whether it landed. Null for a build that
  /// keeps no device settings.
  Future<bool> Function(bool open, double height)? persistPanel;

  /// Writes `aiTrailAutoOpen`, answering whether it landed.
  Future<bool> Function(bool autoOpen)? persistAutoOpen;

  /// Where a session's trail file is written. Null until a root binds
  /// it; the header then says the trail is kept in memory.
  TomAiTrailFileStatus? Function(String sessionId)? trailFileFor;

  bool _open = false;
  double _height = defaultHeight;
  bool _autoOpen = true;
  String? _selected;
  final Set<LlmTrailEntryKind> _hidden = {};

  /// Whether the panel is open.
  bool get isOpen => _open;

  /// The panel's height.
  double get height => _height;

  /// Whether a starting run opens the panel.
  bool get autoOpen => _autoOpen;

  /// The selected session, or null for the **All** tab.
  String? get selected => _selected;

  /// One tab each: the sessions with a record in memory, then those with a
  /// docked run and the sessions the user created that have neither yet.
  List<String> get sessions {
    final withRecords = trails?.sessions ?? const <String>[];
    final out = [...withRecords];
    for (final id in _docked.keys) {
      if (!out.contains(id)) out.add(id);
    }
    for (final s in registry.sessions) {
      if (!s.isBuiltIn && !out.contains(s.id)) out.add(s.id);
    }
    return out;
  }

  /// Whether [sessionId] has a run in progress: one the trail records as
  /// running, or a docked run asking the model.
  bool isRunning(String sessionId) =>
      (trails?.isRunning(sessionId) ?? false) ||
      (_docked[sessionId]?.isWorking ?? false);

  /// Whether [sessionId]'s docked run waits for the user's decision.
  bool needsDecision(String sessionId) =>
      _docked[sessionId]?.needsDecision ?? false;

  /// How many sessions have a run in progress — the phone chip's count.
  int get runningCount => sessions.where(isRunning).length;

  final Set<String> _expanded = {};

  /// Whether the collapsible part of the entry [key] is open — a thinking
  /// block, or a long tool result. Kept here rather than in a widget, since
  /// the panel and the phone sheet show the same trail.
  bool isExpanded(String key) => _expanded.contains(key);

  /// Opens or closes the collapsible part of the entry [key].
  void toggleExpanded(String key) {
    if (!_expanded.remove(key)) _expanded.add(key);
    notifyListeners();
  }

  /// The entry kinds the filter hides.
  Set<LlmTrailEntryKind> get hidden => Set.unmodifiable(_hidden);

  /// Takes the stored device state, without writing it back.
  void adopt({bool? open, double? height, bool? autoOpen}) {
    _open = open ?? _open;
    _height = height == null ? _height : _clamp(height);
    _autoOpen = autoOpen ?? _autoOpen;
    notifyListeners();
  }

  static double _clamp(double height) =>
      height < minHeight ? minHeight : height;

  /// Opens or closes the panel, and writes the choice.
  Future<bool> setOpen(bool open) {
    if (_open == open) return Future.value(true);
    _open = open;
    notifyListeners();
    return _writePanel();
  }

  /// Opens the panel when closed, closes it when open.
  Future<bool> toggle() => setOpen(!_open);

  /// Sets the height during a splitter drag. Not written until
  /// [commitHeight], so a drag is one write rather than one per frame.
  void dragHeight(double height) {
    final next = _clamp(height);
    if (next == _height) return;
    _height = next;
    notifyListeners();
  }

  /// Writes the height a drag left.
  Future<bool> commitHeight() => _writePanel();

  Future<bool> _writePanel() async {
    final write = persistPanel;
    return write == null ? false : await write(_open, _height);
  }

  /// Sets whether a starting run opens the panel, and writes it.
  Future<bool> applyAutoOpen(bool autoOpen) async {
    _autoOpen = autoOpen;
    notifyListeners();
    final write = persistAutoOpen;
    return write == null ? false : await write(autoOpen);
  }

  /// The layout reset: the panel back to closed at its default height.
  /// The device keys are cleared by the reset itself.
  void resetLayout() {
    _open = false;
    _height = defaultHeight;
    notifyListeners();
  }

  /// Shows [sessionId]'s tab, or the **All** tab for null.
  void select(String? sessionId) {
    if (_selected == sessionId) return;
    _selected = sessionId;
    notifyListeners();
  }

  /// Closes [sessionId]'s tab: drops its in-memory trail and discards a run
  /// docked there (closing is the rejection). Touches no file.
  void closeSession(String sessionId) {
    if (_selected == sessionId) _selected = null;
    _release(sessionId);
    trails?.clear(sessionId);
    notifyListeners();
  }

  /// Shows or hides [kind] in the trail.
  void toggleKind(LlmTrailEntryKind kind) {
    if (!_hidden.remove(kind)) _hidden.add(kind);
    notifyListeners();
  }

  /// The selected tab's entries, filtered.
  List<LlmTrailEntry> get entries {
    final source = trails;
    if (source == null) return const [];
    final selected = _selected;
    final records = selected == null
        ? [for (final id in source.sessions) ...source.recordsOf(id)]
        : source.recordsOf(selected);
    if (selected == null) {
      // Interleaved by time, then by session order for one instant.
      records.sort((a, b) {
        final byTime = a.at.compareTo(b.at);
        return byTime != 0 ? byTime : a.seq.compareTo(b.seq);
      });
    }
    return [
      for (final entry in llmTrailEntries(records))
        if (!_hidden.contains(entry.kind)) entry,
    ];
  }

  /// The shown trail as plain text, for *Copy all*.
  String get plainText {
    final all = _selected == null;
    return [
      for (final entry in entries)
        all ? '[${entry.sessionId}] ${entry.plainText}' : entry.plainText,
    ].join('\n\n');
  }

  /// Turns persistence on for a memory-only session through [keep], then
  /// redraws the header, which now names the file the trail is written to.
  Future<void> keepOnDisk(Future<void> Function() keep) async {
    await keep();
    notifyListeners();
  }

  /// Where the trail files go, or null on a build that writes none.
  TomAiTrailDirectoryInfo? get directory => _directory;
  TomAiTrailDirectoryInfo? _directory;

  /// Sets the device's trail directory (null hands the choice back to the
  /// later rules), answering whether the setting was written. Bound by a root
  /// that writes trail files.
  Future<bool> Function(String? path)? applyDirectory;

  /// Shows where the trail files now go.
  void showDirectory(TomAiTrailDirectoryInfo directory) {
    _directory = directory;
    notifyListeners();
  }

  /// What the header says about the selected session's trail file.
  TomAiTrailFileStatus? get fileStatus {
    final selected = _selected;
    if (selected == null) return null;
    return trailFileFor?.call(selected);
  }

  void _onRecord(LlmTrailRecord record) {
    if (record.event is LlmRunStarted && _autoOpen && !_open) {
      unawaited(setOpen(true));
    }
    _changed();
  }

  /// Whether a notification is waiting for the frame being built to end.
  bool _notifyPending = false;

  bool _disposed = false;

  /// A record can arrive while the tree is locked — closing an AI action's dialog
  /// cancels its run from the dialog's `dispose`, and the cancellation is
  /// recorded at once — so the panel is told after that frame, once however
  /// many records arrived in it.
  void _changed() {
    final selected = _selected;
    if (selected != null && !sessions.contains(selected)) _selected = null;
    if (_notifyPending) return;
    _notifyPending = true;
    tomRunAfterBuild(() {
      _notifyPending = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    // Not awaited (woneprpd20): a cancel takes effect when it is called.
    unawaited(_records?.cancel());
    unawaited(_changes?.cancel());
    unawaited(_registryChanges?.cancel());
    for (final id in [..._docked.keys]) {
      _release(id);
    }
    registry.dispose();
    super.dispose();
  }
}

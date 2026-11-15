/// The two instant-editing fields the calendar surfaces share.
///
/// Both edit **one half** of a `DateTime` and leave the other alone, which is
/// what lets the D9 §7 overlay show a date and a time side by side over a
/// single stored instant instead of keeping two half-values in step by hand.
///
/// In both, the text field *is* the value and the picker writes into it. The
/// canonical form (D9 §2.2 `yyyy-MM-dd` and `HH:mm:ss`) is what the document
/// stores, so typing it is exact and lossless; a picker as the source of truth
/// would make the field a mirror that has to be reconciled.
///
/// **This is the timezone boundary (D9 §3.2).** §3 makes UTC at second
/// precision the *canonical storage* form and local the *display* form: "the
/// editor converts to the device's local timezone for rendering and converts
/// user input back to UTC on save". These two fields are where that happens,
/// and they are the only place it happens — the model, the codec and the §4.2
/// expander stay UTC-only, which is what keeps a sync job and an agent
/// deterministic. Before `woneprpc11` both fields worked entirely in UTC, so a
/// user in UTC+8 who typed 17:00 stored 17:00Z and the event landed eight hours
/// away.
///
/// Both are told the frame they show a value in ([CalendarTimeFrame]): the
/// app passes its clock's, which is the device's zone. An **all-day** value is
/// the exception §3.3 requires — it is timezone-free and is shown in
/// [CalendarTimeFrame.utc], exactly as stored, because converting a date-only
/// instant through an offset moves it a day at either end of the world.
library;

import 'package:flutter/material.dart';
import 'package:tom_calendar_model/tom_calendar_model.dart';

/// Edits the **date** of [value], preserving its time of day.
class TomDateField extends StatefulWidget {
  const TomDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.frame,
    this.validator,
  });

  final String label;

  /// The instant being edited; only its `yyyy-MM-dd` is shown.
  final DateTime value;

  /// Receives [value] moved to the typed/picked date, same wall clock —
  /// **always in UTC**, whatever [frame] is.
  final ValueChanged<DateTime> onChanged;

  /// The frame [value] is shown in: the reader's for a point in time (D9
  /// §3.2), [CalendarTimeFrame.utc] for a **timezone-free date** (§3.3).
  ///
  /// All-day values pass `utc`. A date-only instant is not a moment that
  /// happens somewhere — shifting it by an offset moves the day itself, which
  /// is the one conversion §3.3 exists to forbid.
  final CalendarTimeFrame frame;

  /// Additional validation on the composed instant, run after the format check.
  final String? Function(DateTime?)? validator;

  @override
  State<TomDateField> createState() => _TomDateFieldState();
}

class _TomDateFieldState extends State<TomDateField> {
  static final RegExp _pattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _text);
  }

  /// [TomDateField.value]'s wall clock in the frame it is shown in.
  DateTime get _shown => widget.frame.wall(widget.value);

  String get _text {
    final v = _shown;
    String p2(int n) => n.toString().padLeft(2, '0');
    return '${v.year.toString().padLeft(4, '0')}-${p2(v.month)}-${p2(v.day)}';
  }

  @override
  void didUpdateWidget(TomDateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Overwrite only when the text parses to a *different* date than the one
    // now held. Half-typed text is left alone — the validator speaks to that —
    // because rewriting it mid-keystroke would fight the cursor.
    final typed = _parse(_controller.text);
    if (typed != null && typed != widget.value.toUtc()) _syncText();
  }

  /// Rewrites the controller **after** the frame.
  ///
  /// A controller write notifies synchronously, and `didUpdateWidget` runs
  /// inside the owning `Form`'s build — so writing there marks the form dirty
  /// mid-build and throws. Latent until `woneprpc11`: the guard above only
  /// fires when the same text now means a different instant, which before the
  /// §3.2 conversion needed the *value* to change under a parked field.
  /// Toggling all-day changes the frame instead, and the same text starts
  /// meaning something else.
  void _syncText() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final text = _text;
      if (_controller.text != text) _controller.text = text;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The typed date carrying [TomDateField.value]'s wall clock, or `null`
  /// when the text is not a canonical date.
  DateTime? _parse(String text) {
    if (!_pattern.hasMatch(text)) return null;
    final date = DateTime.tryParse('${text}T00:00:00Z');
    if (date == null) return null;
    return _compose(date.year, date.month, date.day);
  }

  /// The shown wall clock moved to `y-m-d`, returned in **UTC**.
  ///
  /// The wall clock comes from the same frame the date does, which is what
  /// makes "change the date, keep the time" mean what a user reading the two
  /// fields expects — composing a local date onto a UTC time of day would move
  /// the event by the offset on every date edit.
  DateTime _compose(int y, int m, int d) {
    final v = _shown;
    return widget.frame.instant(y, m, d, v.hour, v.minute, v.second);
  }

  Future<void> _pick() async {
    final picked = await showDatePicker(
      context: context,
      // The shown date, not the stored one: the picker opens on the day the
      // field is displaying, which for a timed event in UTC+8 late in the
      // evening is not the UTC day.
      initialDate: _shown,
      firstDate: DateTime.utc(2000),
      lastDate: DateTime.utc(2100),
    );
    if (picked == null) return;
    final composed = _compose(picked.year, picked.month, picked.day);
    widget.onChanged(composed);
    if (mounted) setState(() => _controller.text = _text);
  }

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: _controller,
        decoration: InputDecoration(
          labelText: widget.label,
          suffixIcon: IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _pick,
          ),
        ),
        validator: (_) {
          final parsed = _parse(_controller.text);
          if (parsed == null) return 'Use yyyy-MM-dd';
          return widget.validator?.call(parsed);
        },
        onChanged: (text) {
          final parsed = _parse(text);
          if (parsed != null) widget.onChanged(parsed);
        },
      );
}

/// Edits the **time of day** of [value], preserving its date.
///
/// Seconds are shown because D9 §2.2 stores them: hiding a field the format
/// keeps would silently zero an imported event's odd start time on the first
/// unrelated edit.
class TomTimeField extends StatefulWidget {
  const TomTimeField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.frame,
    this.validator,
  });

  final String label;
  final DateTime value;

  /// Receives [value] at the typed/picked time of day, **in UTC** (D9 §3.2).
  final ValueChanged<DateTime> onChanged;

  /// The frame the time of day is read in — the reader's (D9 §3.2).
  final CalendarTimeFrame frame;
  final String? Function(DateTime?)? validator;

  @override
  State<TomTimeField> createState() => _TomTimeFieldState();
}

class _TomTimeFieldState extends State<TomTimeField> {
  static final RegExp _pattern = RegExp(r'^(\d{2}):(\d{2}):(\d{2})$');

  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _text);
  }

  /// A time of day is always a point in time: an all-day appointment has no
  /// time field at all (§3.3), which is why the `utc` exception is the date
  /// field's alone.
  DateTime get _shown => widget.frame.wall(widget.value);

  String get _text {
    final v = _shown;
    String p2(int n) => n.toString().padLeft(2, '0');
    return '${p2(v.hour)}:${p2(v.minute)}:${p2(v.second)}';
  }

  @override
  void didUpdateWidget(TomTimeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_parse(_controller.text) != widget.value.toUtc()) _syncText();
  }

  /// See `_TomDateFieldState._syncText` — same hazard, same deferral.
  void _syncText() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final text = _text;
      if (_controller.text != text) _controller.text = text;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  DateTime? _parse(String text) {
    final match = _pattern.firstMatch(text);
    if (match == null) return null;
    final h = int.parse(match.group(1)!);
    final m = int.parse(match.group(2)!);
    final s = int.parse(match.group(3)!);
    if (h > 23 || m > 59 || s > 59) return null;
    return _compose(h, m, s);
  }

  /// The shown date at `h:m:s` in the frame, returned in **UTC**.
  DateTime _compose(int h, int m, int s) {
    final v = _shown;
    return widget.frame.instant(v.year, v.month, v.day, h, m, s);
  }

  Future<void> _pick() async {
    final v = _shown;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: v.hour, minute: v.minute),
    );
    if (picked == null) return;
    // The picker has no seconds, so picking a time zeroes them — an explicit
    // consequence of using it, not a silent truncation of what was typed.
    final composed = _compose(picked.hour, picked.minute, 0);
    String p2(int n) => n.toString().padLeft(2, '0');
    _controller.text = '${p2(picked.hour)}:${p2(picked.minute)}:00';
    widget.onChanged(composed);
  }

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: _controller,
        decoration: InputDecoration(
          labelText: widget.label,
          suffixIcon: IconButton(
            icon: const Icon(Icons.schedule),
            onPressed: _pick,
          ),
        ),
        validator: (_) {
          final parsed = _parse(_controller.text);
          if (parsed == null) return 'Use HH:mm:ss';
          return widget.validator?.call(parsed);
        },
        onChanged: (text) {
          final parsed = _parse(text);
          if (parsed != null) widget.onChanged(parsed);
        },
      );
}

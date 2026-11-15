/// An appointment editor over `tom_calendar_model`'s [CalendarAppointment].
library;

import 'package:flutter/material.dart';
import 'package:tom_calendar_model/tom_calendar_model.dart';

import 'date_time_fields.dart';
import 'recurrence_field.dart';


/// Edits one appointment: title, all-day form, start/end, location,
/// description, and — unless suppressed — its recurrence rule.
///
/// The editor holds a **draft** and hands the finished appointment to
/// [onSubmit]; it writes nothing itself. Which list the result belongs in, and
/// whether it replaces a series or detaches one occurrence, is a question
/// the caller has already answered — the overlay would have to guess.
///
/// The all-day toggle routes through [CalendarAppointmentEditing.setAllDay], so
/// the one place that invents a wall clock stays the one place, and the shown
/// pickers switch between date-only and date+time as a consequence of the
/// stored form rather than as a parallel UI state.
class TomAppointmentEditor extends StatefulWidget {
  const TomAppointmentEditor({
    super.key,
    required this.initial,
    required this.onSubmit,
    this.onCancel,
    this.heading,
    required this.frame,
    this.showRecurrence = true,
    this.submitLabel = 'Save',
  });

  /// The appointment to edit. Never mutated — the draft is a copy.
  final CalendarAppointment initial;

  /// The frame the reader's days and times are in — the app's
  /// clock's, which is the device's zone.
  final CalendarTimeFrame frame;

  final ValueChanged<CalendarAppointment> onSubmit;
  final VoidCallback? onCancel;

  final String? heading;

  /// Whether the repeat control is offered.
  ///
  /// False when editing a **single occurrence** : the result is detached
  /// from its series and by definition does not recur, so a repeat control
  /// there would offer to create a second series out of an exception.
  final bool showRecurrence;

  final String submitLabel;

  @override
  State<TomAppointmentEditor> createState() =>
      _TomAppointmentEditorState();
}

class _TomAppointmentEditorState extends State<TomAppointmentEditor> {
  final _formKey = GlobalKey<FormState>();
  late CalendarAppointment _draft;
  late final TextEditingController _title;
  late final TextEditingController _location;
  late final TextEditingController _description;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial.copy();
    _title = TextEditingController(text: _draft.title);
    _location = TextEditingController(text: _draft.location ?? '');
    _description = TextEditingController(text: _draft.description ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _description.dispose();
    super.dispose();
  }

  void _setAllDay(bool allDay) => setState(() {
        // The day the user is reading is the device's.
        _draft = CalendarAppointmentEditing.setAllDay(
          _draft,
          allDay,
          frame: widget.frame,
        );
      });

  /// `end >= start`, in whichever form the draft is currently in.
  ///
  /// Checked against the *candidate* rather than the draft, because a field's
  /// validator runs on submit over text that may not have been committed yet.
  String? _endNotBefore(DateTime? candidate) {
    if (candidate == null) return null;
    if (candidate.isBefore(_draft.start)) {
      return _draft.allDay
          ? 'Last day must be on or after the first'
          : 'End must be at or after the start';
    }
    return null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    widget.onSubmit(CalendarAppointment(
      id: _draft.id,
      title: _title.text.trim(),
      allDay: _draft.allDay,
      start: _draft.start,
      end: _draft.end,
      description: _emptyToNull(_description.text),
      location: _emptyToNull(_location.text),
      createdIn: _draft.createdIn,
      recurrence: widget.showRecurrence ? _draft.recurrence : null,
      exceptions: widget.showRecurrence ? _draft.exceptions : const [],
    ));
  }

  /// The model omits empty optional fields, so a field the user cleared must come
  /// back as absent rather than as `''` — otherwise clearing a description
  /// changes the bytes without changing the meaning.
  static String? _emptyToNull(String text) {
    final trimmed = text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey('appointment-editor'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.heading != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                widget.heading!,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          TextFormField(
            key: const ValueKey('appointment-title'),
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title'),
            validator: (value) =>
                (value ?? '').trim().isEmpty ? 'A title is required' : null,
          ),
          SwitchListTile(
            key: const ValueKey('appointment-allday'),
            contentPadding: EdgeInsets.zero,
            title: const Text('All day'),
            value: _draft.allDay,
            onChanged: _setAllDay,
          ),
          ..._instantRow(
            label: 'Starts',
            dateKey: 'appointment-start-date',
            timeKey: 'appointment-start-time',
            value: _draft.start,
            onChanged: (value) => setState(() => _draft.start = value),
          ),
          const SizedBox(height: 8),
          ..._instantRow(
            label: _draft.allDay ? 'Last day' : 'Ends',
            dateKey: 'appointment-end-date',
            timeKey: 'appointment-end-time',
            value: _draft.end,
            onChanged: (value) => setState(() => _draft.end = value),
            validator: _endNotBefore,
          ),
          if (!_draft.allDay)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              // The fields above are the device's clock. This is the same
              // moment as everyone else reads it.
              child: Text(
                calendarDescribeTimes(_draft, local: widget.frame),
                key: const ValueKey('appointment-times'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 8),
          TextFormField(
            key: const ValueKey('appointment-location'),
            controller: _location,
            decoration: const InputDecoration(labelText: 'Location'),
          ),
          TextFormField(
            key: const ValueKey('appointment-description'),
            controller: _description,
            decoration: const InputDecoration(labelText: 'Description'),
            minLines: 2,
            maxLines: 4,
          ),
          if (widget.showRecurrence) ...[
            const SizedBox(height: 16),
            TomRecurrenceField(
              // Rebuilt from scratch when the form flips, because `UNTIL` has
              // to change value type with it (RFC 5545 ties it to `DTSTART`).
              //
              // And when the start crosses midnight in one frame and not the
              // other, because the days the rule names are shown in the
              // reader's frame and stored in UTC.
              key: ValueKey('recurrence-${_draft.allDay}-'
                  '${_draft.allDay ? 0 : widget.frame.dayShift(_draft.start)}'),
              value: _draft.recurrence,
              allDay: _draft.allDay,
              seriesStart: _draft.start,
              frame: widget.frame,
              onChanged: (value) =>
                  setState(() => _draft.recurrence = value),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                key: const ValueKey('appointment-cancel'),
                onPressed: widget.onCancel,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const ValueKey('appointment-save'),
                onPressed: _submit,
                child: Text(widget.submitLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// A date field, plus a time field when the draft is timed.
  ///
  /// The two edit disjoint halves of the same instant, so there is no third
  /// combined value to keep in step: whichever field changed composes its half
  /// onto the other's.
  List<Widget> _instantRow({
    required String label,
    required String dateKey,
    required String timeKey,
    required DateTime value,
    required ValueChanged<DateTime> onChanged,
    String? Function(DateTime?)? validator,
  }) =>
      [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: TomDateField(
                key: ValueKey(dateKey),
                label: label,
                value: value,
                onChanged: onChanged,
                validator: validator,
                // An all-day value is timezone-free, so it is shown
                // exactly as stored. Everything else is a point in time and is
                // shown in the reader's frame.
                frame: _draft.allDay ? CalendarTimeFrame.utc : widget.frame,
              ),
            ),
            if (!_draft.allDay) ...[
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TomTimeField(
                  key: ValueKey(timeKey),
                  label: 'Time',
                  value: value,
                  onChanged: onChanged,
                  frame: widget.frame,
                  validator: validator,
                ),
              ),
            ],
          ],
        ),
      ];
}

/// Shows [TomAppointmentEditor] in a dialog, returning the edited
/// appointment or `null` when the user cancelled.
Future<CalendarAppointment?> showTomAppointmentEditor(
  BuildContext context, {
  required CalendarAppointment initial,
  required CalendarTimeFrame frame,
  String? heading,
  bool showRecurrence = true,
  String submitLabel = 'Save',
}) {
  return showDialog<CalendarAppointment>(
    context: context,
    builder: (context) => Dialog(
      key: const ValueKey('appointment-dialog'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: TomAppointmentEditor(
            initial: initial,
            frame: frame,
            heading: heading,
            showRecurrence: showRecurrence,
            submitLabel: submitLabel,
            onSubmit: (appointment) =>
                Navigator.of(context).pop(appointment),
            onCancel: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    ),
  );
}

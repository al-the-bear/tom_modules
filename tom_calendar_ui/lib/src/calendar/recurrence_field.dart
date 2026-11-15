/// The D9 §4.1 repeat control, and the §4.3 read-only degradation.
library;

import 'package:flutter/material.dart';
import 'package:tom_calendar_model/tom_calendar_model.dart';

import 'date_time_fields.dart';

/// How a monthly rule picks its day.
enum _MonthlyMode { dayOfMonth, ordinalWeekday }

/// How a series stops.
enum _EndMode { never, count, until }

/// Edits an RRULE, restricted to exactly the D9 §4.1 subset.
///
/// The control emits **only** rules the expander can read back
/// ([CalendarRecurrenceRule.format] is the inverse of `tryParse`), which is what
/// makes "what you built is what reopens" true rather than hoped for.
///
/// A rule outside the subset is shown **read-only** with a custom-recurrence
/// badge (§4.3, degrade never delete). It is not silently rewritten into the
/// nearest supported rule, and not offered for editing through controls that
/// could not express it — either would lose the user's `BYSETPOS` the first
/// time they changed the title.
class TomRecurrenceField extends StatefulWidget {
  const TomRecurrenceField({
    super.key,
    required this.value,
    required this.allDay,
    required this.onChanged,
    required this.seriesStart,
    required this.frame,
  });

  /// The current RRULE value, verbatim; `null` for "does not repeat".
  final String? value;

  /// Selects the `UNTIL` value type (RFC 5545 requires it to match `DTSTART`).
  final bool allDay;

  final ValueChanged<String?> onChanged;

  /// Seeds the defaults, so "monthly" starts on the day the series starts
  /// rather than on the 1st.
  final DateTime seriesStart;

  /// Whose day the controls show. A timed series is stored against its UTC
  /// start, so the days its rule names are UTC days; the user reads the
  /// device's. An all-day series is timezone-free and has no frame (§3.3).
  final CalendarTimeFrame frame;

  @override
  State<TomRecurrenceField> createState() => _TomRecurrenceFieldState();
}

class _TomRecurrenceFieldState extends State<TomRecurrenceField> {
  static const _weekdayLabels = <int, String>{
    DateTime.monday: 'Mo',
    DateTime.tuesday: 'Tu',
    DateTime.wednesday: 'We',
    DateTime.thursday: 'Th',
    DateTime.friday: 'Fr',
    DateTime.saturday: 'Sa',
    DateTime.sunday: 'Su',
  };
  static const _weekdayCodes = <int, String>{
    DateTime.monday: 'MO',
    DateTime.tuesday: 'TU',
    DateTime.wednesday: 'WE',
    DateTime.thursday: 'TH',
    DateTime.friday: 'FR',
    DateTime.saturday: 'SA',
    DateTime.sunday: 'SU',
  };

  CalendarRecurrenceFreq? _freq;
  int _interval = 1;
  final Set<int> _weekdays = {};
  _MonthlyMode _monthlyMode = _MonthlyMode.dayOfMonth;
  late int _monthDay;
  int _ordinal = 1;
  late int _ordinalWeekday;
  _EndMode _endMode = _EndMode.never;
  int _count = 10;
  /// The last day of the series, timezone-free, as the user reads it.
  late DateTime _until;

  /// How far the shown day is ahead of the stored (UTC) one.
  late final int _shift =
      widget.allDay ? 0 : widget.frame.dayShift(widget.seriesStart);

  DateTime _shownDate(DateTime instant) => widget.allDay
      ? DateTime.utc(instant.year, instant.month, instant.day)
      : widget.frame.dateOf(instant);

  late final TextEditingController _intervalController;
  late final TextEditingController _countController;

  @override
  void initState() {
    super.initState();
    final start = _shownDate(widget.seriesStart.toUtc());
    _monthDay = start.day;
    _ordinalWeekday = start.weekday;
    _until = DateTime.utc(start.year + 1, start.month, start.day);

    final stored = widget.value == null
        ? null
        : CalendarRecurrenceRule.tryParse(widget.value!,
            start: widget.seriesStart);
    final rule = stored == null
        ? null
        : CalendarRecurrenceEditing.shiftDays(stored, _shift);
    if (rule != null) {
      _freq = rule.freq;
      _interval = rule.interval;
      for (final d in rule.byDay) {
        if (d.ordinal == null) {
          _weekdays.add(d.weekday);
        } else {
          _monthlyMode = _MonthlyMode.ordinalWeekday;
          _ordinal = d.ordinal!;
          _ordinalWeekday = d.weekday;
        }
      }
      if (rule.byMonthDay.isNotEmpty) {
        _monthlyMode = _MonthlyMode.dayOfMonth;
        _monthDay = rule.byMonthDay.first;
      }
      if (rule.count != null) {
        _endMode = _EndMode.count;
        _count = rule.count!;
      } else if (rule.until != null) {
        _endMode = _EndMode.until;
        _until = _shownDate(rule.until!);
      }
    }
    _intervalController = TextEditingController(text: '$_interval');
    _countController = TextEditingController(text: '$_count');
  }

  @override
  void dispose() {
    _intervalController.dispose();
    _countController.dispose();
    super.dispose();
  }

  /// Rebuilds the rule from the controls and hands it up.
  void _emit() {
    final freq = _freq;
    if (freq == null) {
      widget.onChanged(null);
      return;
    }
    final rule = CalendarRecurrenceRule(
      freq: freq,
      interval: _interval,
      count: _endMode == _EndMode.count ? _count : null,
      until: _endMode == _EndMode.until ? _boundedUntil() : null,
      byDay: [
        if (freq == CalendarRecurrenceFreq.weekly)
          for (final d in _sorted(_weekdays)) CalendarByDay(d),
        if (freq == CalendarRecurrenceFreq.monthly &&
            _monthlyMode == _MonthlyMode.ordinalWeekday)
          CalendarByDay(_ordinalWeekday, _ordinal),
      ],
      byMonthDay: [
        if (freq == CalendarRecurrenceFreq.monthly &&
            _monthlyMode == _MonthlyMode.dayOfMonth)
          _monthDay,
      ],
    );
    widget.onChanged(CalendarRecurrenceEditing.shiftDays(rule, -_shift)
        .format(allDay: widget.allDay));
  }

  /// A timed `UNTIL` bounds the *whole* chosen day, so a series that ends "on
  /// the 31st" includes the 31st's occurrence rather than stopping the night
  /// before it.
  ///
  /// The day is the one the user picked, so for a timed series it ends when
  /// that day ends **in the frame they read it in**.
  DateTime _boundedUntil() => widget.allDay
      ? DateTime.utc(_until.year, _until.month, _until.day)
      : widget.frame
          .instant(_until.year, _until.month, _until.day, 23, 59, 59);

  static List<int> _sorted(Set<int> days) => days.toList()..sort();

  String get _unit => switch (_freq) {
        CalendarRecurrenceFreq.daily => _interval == 1 ? 'day' : 'days',
        CalendarRecurrenceFreq.weekly => _interval == 1 ? 'week' : 'weeks',
        CalendarRecurrenceFreq.monthly => _interval == 1 ? 'month' : 'months',
        CalendarRecurrenceFreq.yearly => _interval == 1 ? 'year' : 'years',
        null => '',
      };

  @override
  Widget build(BuildContext context) {
    if (!CalendarRecurrenceEditing.isInterpretable(widget.value,
        start: widget.seriesStart)) {
      return _customBadge(context);
    }
    return Column(
      key: const ValueKey('recurrence-editor'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<CalendarRecurrenceFreq?>(
          key: const ValueKey('recurrence-freq'),
          initialValue: _freq,
          decoration: const InputDecoration(labelText: 'Repeat'),
          items: const [
            DropdownMenuItem(value: null, child: Text('Does not repeat')),
            DropdownMenuItem(
                value: CalendarRecurrenceFreq.daily, child: Text('Daily')),
            DropdownMenuItem(
                value: CalendarRecurrenceFreq.weekly, child: Text('Weekly')),
            DropdownMenuItem(
                value: CalendarRecurrenceFreq.monthly, child: Text('Monthly')),
            DropdownMenuItem(
                value: CalendarRecurrenceFreq.yearly, child: Text('Yearly')),
          ],
          onChanged: (value) => setState(() {
            _freq = value;
            _emit();
          }),
        ),
        if (_freq != null) ...[
          const SizedBox(height: 8),
          _intervalRow(),
          if (_freq == CalendarRecurrenceFreq.weekly) _weekdayChips(),
          if (_freq == CalendarRecurrenceFreq.monthly) ..._monthlyControls(),
          const SizedBox(height: 8),
          ..._endControls(),
        ],
      ],
    );
  }

  Widget _customBadge(BuildContext context) => Column(
        key: const ValueKey('recurrence-custom'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Chip(
                avatar: Icon(Icons.repeat, size: 16),
                label: Text('Custom recurrence'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SelectableText(
                  widget.value!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          Text(
            'This rule uses parts this editor does not edit. It is kept exactly as '
            'written and the series shows its first occurrence.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );

  Widget _intervalRow() => Row(
        children: [
          const Text('Every'),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: TextFormField(
              key: const ValueKey('recurrence-interval'),
              controller: _intervalController,
              keyboardType: TextInputType.number,
              onChanged: (text) {
                final n = int.tryParse(text);
                if (n == null || n < 1) return;
                setState(() {
                  _interval = n;
                  _emit();
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          Text(_unit),
        ],
      );

  Widget _weekdayChips() => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(
          spacing: 4,
          children: [
            for (final entry in _weekdayLabels.entries)
              FilterChip(
                key: ValueKey('recurrence-weekday-${_weekdayCodes[entry.key]}'),
                label: Text(entry.value),
                selected: _weekdays.contains(entry.key),
                onSelected: (on) => setState(() {
                  if (on) {
                    _weekdays.add(entry.key);
                  } else {
                    _weekdays.remove(entry.key);
                  }
                  _emit();
                }),
              ),
          ],
        ),
      );

  List<Widget> _monthlyControls() => [
        const SizedBox(height: 8),
        SegmentedButton<_MonthlyMode>(
          key: const ValueKey('recurrence-monthly-mode'),
          segments: const [
            ButtonSegment(
                value: _MonthlyMode.dayOfMonth, label: Text('On a day')),
            ButtonSegment(
                value: _MonthlyMode.ordinalWeekday,
                label: Text('On a weekday')),
          ],
          selected: {_monthlyMode},
          onSelectionChanged: (selection) => setState(() {
            _monthlyMode = selection.first;
            _emit();
          }),
        ),
        const SizedBox(height: 8),
        if (_monthlyMode == _MonthlyMode.dayOfMonth)
          DropdownButtonFormField<int>(
            key: const ValueKey('recurrence-monthday'),
            initialValue: _monthDay,
            decoration: const InputDecoration(labelText: 'Day of month'),
            items: [
              for (var d = 1; d <= 31; d++)
                DropdownMenuItem(value: d, child: Text('$d')),
            ],
            onChanged: (value) => setState(() {
              if (value != null) _monthDay = value;
              _emit();
            }),
          )
        else
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: const ValueKey('recurrence-ordinal'),
                  initialValue: _ordinal,
                  decoration: const InputDecoration(labelText: 'Which'),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('First')),
                    DropdownMenuItem(value: 2, child: Text('Second')),
                    DropdownMenuItem(value: 3, child: Text('Third')),
                    DropdownMenuItem(value: 4, child: Text('Fourth')),
                    DropdownMenuItem(value: -1, child: Text('Last')),
                  ],
                  onChanged: (value) => setState(() {
                    if (value != null) _ordinal = value;
                    _emit();
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: const ValueKey('recurrence-ordinal-weekday'),
                  initialValue: _ordinalWeekday,
                  decoration: const InputDecoration(labelText: 'Weekday'),
                  items: [
                    for (final entry in _weekdayLabels.entries)
                      DropdownMenuItem(
                          value: entry.key, child: Text(entry.value)),
                  ],
                  onChanged: (value) => setState(() {
                    if (value != null) _ordinalWeekday = value;
                    _emit();
                  }),
                ),
              ),
            ],
          ),
      ];

  List<Widget> _endControls() => [
        DropdownButtonFormField<_EndMode>(
          key: const ValueKey('recurrence-end'),
          initialValue: _endMode,
          decoration: const InputDecoration(labelText: 'Ends'),
          items: const [
            DropdownMenuItem(value: _EndMode.never, child: Text('Never')),
            DropdownMenuItem(value: _EndMode.count, child: Text('After')),
            DropdownMenuItem(value: _EndMode.until, child: Text('On date')),
          ],
          onChanged: (value) => setState(() {
            if (value != null) _endMode = value;
            _emit();
          }),
        ),
        if (_endMode == _EndMode.count)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  child: TextFormField(
                    key: const ValueKey('recurrence-count'),
                    controller: _countController,
                    keyboardType: TextInputType.number,
                    onChanged: (text) {
                      final n = int.tryParse(text);
                      if (n == null || n < 1) return;
                      setState(() {
                        _count = n;
                        _emit();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                const Text('occurrences'),
              ],
            ),
          ),
        if (_endMode == _EndMode.until)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TomDateField(
              key: const ValueKey('recurrence-until'),
              label: 'Until',
              // A day, not a moment: shown exactly as held.
              frame: CalendarTimeFrame.utc,
              value: _until,
              onChanged: (value) => setState(() {
                _until = value;
                _emit();
              }),
            ),
          ),
      ];
}

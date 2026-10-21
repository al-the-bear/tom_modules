/// Todo ids by the workspace's date-code convention.
///
/// `<base>_<code>-<slug>`: the base is the series the user names, the code is
/// four letters derived from the local date and hour, the slug is optional.
/// The encoding is the workspace id-prefix tool's, letter for letter, so an id
/// minted here is the id that tool would have produced in the same hour.
library;

/// The 31 day letters: `a`–`z` for 1–26, then five that keep the code one
/// character wide.
const List<String> _dayLetters = [
  'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', //
  'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', //
  'ä', 'ñ', 'ö', 'ß', 'ü',
];

String _letter(int offset) => String.fromCharCode(0x61 + offset);

/// The four-letter code for [when], read in its own (local) time: year
/// (`a` = 2026), month, day of month, hour.
String tomTodoDateCode(DateTime when) {
  if (when.year < 2026 || when.year > 2051) {
    throw RangeError.range(when.year, 2026, 2051, 'year');
  }
  return '${_letter(when.year - 2026)}${_letter(when.month - 1)}'
      '${_dayLetters[when.day - 1]}${_letter(when.hour)}';
}

/// [text] as an id slug: lower case, words joined by `-`, at most 40
/// characters.
String tomTodoIdSlug(String text) {
  final words = text
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.isNotEmpty);
  final out = StringBuffer();
  for (final word in words) {
    final next = out.isEmpty ? word : '-$word';
    if (out.length + next.length > 40) break;
    out.write(next);
  }
  return out.toString();
}

/// A minted id.
String tomMintTodoId(String base, DateTime when, {String slug = ''}) {
  final s = tomTodoIdSlug(slug);
  return '${base}_${tomTodoDateCode(when)}${s.isEmpty ? '' : '-$s'}';
}

final RegExp _idShape = RegExp(
  r'^([A-Za-z][A-Za-z0-9]*)_([a-zäñößü]{4})(?:-|$)',
);

/// The base and date code of [id], or null when it does not have the shape.
({String base, String code})? tomSplitTodoId(String id) {
  final m = _idShape.firstMatch(id);
  return m == null ? null : (base: m.group(1)!, code: m.group(2)!);
}

/// Whether [base] is a valid base id: a letter, then letters and digits.
bool tomIsTodoBase(String base) =>
    RegExp(r'^[A-Za-z][A-Za-z0-9]*$').hasMatch(base);

/// The ids among [existing] that share [id]'s base under a different date
/// code — the todos a `<base>*` iteration would also take.
List<String> tomTodoStemReuse(String id, Iterable<String> existing) {
  final mine = tomSplitTodoId(id);
  if (mine == null) return const [];
  return [
    for (final other in existing)
      if (tomSplitTodoId(other) case final o?
          when o.base == mine.base && o.code != mine.code)
        other,
  ];
}

/// The warning for [reuse], or null when there is none.
String? tomTodoStemReuseWarning(String id, List<String> reuse) {
  final base = tomSplitTodoId(id)?.base;
  if (base == null || reuse.isEmpty) return null;
  return '`$base` is used by `${reuse.first}`'
      '${reuse.length > 1 ? ' and ${reuse.length - 1} more' : ''}; '
      'a `$base*` iteration will take both.';
}

/// The base a todo added after [previousId] is offered: the same series with
/// its number one past the highest the folder uses (`wonetestb15` →
/// `wonetestb16`), or the previous base when it carries no number.
String tomNextTodoBase(String previousId, Iterable<String> existing) {
  final previous = tomSplitTodoId(previousId)?.base ?? previousId;
  final m = RegExp(r'^(.*?)(\d+)$').firstMatch(previous);
  if (m == null) return previous;
  final series = m.group(1)!;
  var highest = int.parse(m.group(2)!);
  for (final id in existing) {
    final base = tomSplitTodoId(id)?.base;
    if (base == null || !base.startsWith(series)) continue;
    final n = int.tryParse(base.substring(series.length));
    if (n != null && n > highest) highest = n;
  }
  return '$series${highest + 1}';
}

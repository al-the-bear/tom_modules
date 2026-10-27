/// What a file tree shows — ordered rules, the last match deciding, and
/// named presets.
library;

import 'package:tom_basics/utilities.dart';
import 'package:meta/meta.dart';
import 'package:tom_todo_model/tom_todo_model.dart';

/// What the filter knows about one entry when it decides.
class ForgeFilterSubject {
  /// The path relative to the root, `/`-separated.
  final String path;

  /// The entry's own name.
  final String name;

  final bool isDirectory;

  /// Whether a `.gitignore` in the root or below ignores it.
  final bool gitignored;

  const ForgeFilterSubject({
    required this.path,
    required this.name,
    required this.isDirectory,
    this.gitignored = false,
  });

  /// The final extension, lower case, without the dot: `md` for `a.md`, `env`
  /// for `.env` and for `x.env`, empty when there is none.
  String get extension {
    final lower = name.toLowerCase();
    final dot = lower.lastIndexOf('.');
    if (dot == -1) return '';
    return lower.substring(dot + 1);
  }
}

/// One rule. A rule that **matches** an entry says show or hide;
/// the last matching rule decides, and an entry no rule matches is shown.
sealed class ForgeFilterRule {
  const ForgeFilterRule();

  /// Whether this rule speaks to [subject].
  bool matches(ForgeFilterSubject subject);

  /// Whether, when it speaks, it shows.
  bool get shows;

  /// The rule as one line — what the hidden list says hid an entry.
  String describe();

  /// The persisted form.
  Map<String, Object?> encode();

  /// Reads a persisted rule, or null for one this build does not know.
  static ForgeFilterRule? decode(Object? value) {
    if (value is! Map) return null;
    bool flag(Object? v) => v == true || v == 'show';
    switch (value['rule']) {
      case 'glob':
        final glob = value['glob'];
        if (glob is! String || glob.isEmpty) return null;
        return ForgeGlobRule(glob, include: flag(value['include']));
      case 'extensions':
        final list = value['extensions'];
        if (list is! List) return null;
        return ForgeExtensionRule([
          for (final e in list)
            if (e is String && e.isNotEmpty) e,
        ], include: flag(value['include']));
      case 'hidden':
        return ForgeHiddenRule(show: flag(value['show']));
      case 'gitignored':
        return ForgeGitignoredRule(show: flag(value['show']));
      case 'todoSiblings':
        return ForgeTodoSiblingsRule(show: flag(value['show']));
    }
    return null;
  }
}

/// `include: <glob>` / `exclude: <glob>` over the path relative to the root.
class ForgeGlobRule extends ForgeFilterRule {
  final TomGlob glob;
  final bool include;

  ForgeGlobRule(String pattern, {required this.include})
    : glob = TomGlob(pattern);

  @override
  bool matches(ForgeFilterSubject subject) => glob.matches(subject.path);

  @override
  bool get shows => include;

  @override
  String describe() => '${include ? 'include' : 'exclude'}: ${glob.pattern}';

  @override
  Map<String, Object?> encode() => {
    'rule': 'glob',
    'glob': glob.pattern,
    'include': include,
  };
}

/// `extensions: [...]`, include or exclude; folders never match.
class ForgeExtensionRule extends ForgeFilterRule {
  final List<String> extensions;
  final bool include;

  ForgeExtensionRule(Iterable<String> extensions, {required this.include})
    : extensions = [
        for (final e in extensions) e.toLowerCase().replaceFirst('.', ''),
      ];

  @override
  bool matches(ForgeFilterSubject subject) =>
      !subject.isDirectory && extensions.contains(subject.extension);

  @override
  bool get shows => include;

  @override
  String describe() =>
      '${include ? 'include' : 'exclude'} extensions: ${extensions.join(', ')}';

  @override
  Map<String, Object?> encode() => {
    'rule': 'extensions',
    'extensions': extensions,
    'include': include,
  };
}

/// `hidden: show | hide` — entries whose name starts with `.`.
class ForgeHiddenRule extends ForgeFilterRule {
  final bool show;

  const ForgeHiddenRule({required this.show});

  @override
  bool matches(ForgeFilterSubject subject) => subject.name.startsWith('.');

  @override
  bool get shows => show;

  @override
  String describe() => 'hidden entries: ${show ? 'show' : 'hide'}';

  @override
  Map<String, Object?> encode() => {'rule': 'hidden', 'show': show};
}

/// `gitignored: show | hide`.
class ForgeGitignoredRule extends ForgeFilterRule {
  final bool show;

  const ForgeGitignoredRule({required this.show});

  @override
  bool matches(ForgeFilterSubject subject) => subject.gitignored;

  @override
  bool get shows => show;

  @override
  String describe() => 'gitignored entries: ${show ? 'show' : 'hide'}';

  @override
  Map<String, Object?> encode() => {'rule': 'gitignored', 'show': show};
}

/// `todoSiblings: show | hide` — the `-archived` and `-deleted` siblings of
/// todo files.
class ForgeTodoSiblingsRule extends ForgeFilterRule {
  final bool show;

  const ForgeTodoSiblingsRule({required this.show});

  @override
  bool matches(ForgeFilterSubject subject) {
    if (subject.isDirectory) return false;
    final todo = TomTodoFileName.parse(subject.name);
    return todo != null && todo.sibling != TomTodoFileSibling.live;
  }

  @override
  bool get shows => show;

  @override
  String describe() =>
      'archived and deleted todo files: ${show ? 'show' : 'hide'}';

  @override
  Map<String, Object?> encode() => {'rule': 'todoSiblings', 'show': show};
}

/// A filter's verdict on one entry.
class ForgeFilterVerdict {
  final bool shown;

  /// The rule that decided, or null when none matched (shown by default).
  final ForgeFilterRule? rule;

  const ForgeFilterVerdict(this.shown, this.rule);
}

/// An ordered list of rules.
class ForgeFilter {
  final List<ForgeFilterRule> rules;

  const ForgeFilter(this.rules);

  /// The last matching rule decides; no match shows.
  ForgeFilterVerdict evaluate(ForgeFilterSubject subject) {
    for (final rule in rules.reversed) {
      if (rule.matches(subject)) return ForgeFilterVerdict(rule.shows, rule);
    }
    return const ForgeFilterVerdict(true, null);
  }

  /// Whether a rule hides [subject] **with everything below it** — a hidden or
  /// gitignored folder is not descended into, the way git does not descend
  /// into an ignored folder; any other hiding of a folder still lets what is
  /// inside it show.
  bool hidesSubtree(ForgeFilterSubject subject, ForgeFilterVerdict verdict) {
    if (!subject.isDirectory || verdict.shown) return false;
    final rule = verdict.rule;
    return rule is ForgeHiddenRule || rule is ForgeGitignoredRule;
  }

  List<Map<String, Object?>> encode() => [for (final r in rules) r.encode()];

  static ForgeFilter decode(Object? value) => ForgeFilter([
    if (value is List)
      for (final r in value) ?ForgeFilterRule.decode(r),
  ]);
}

/// A named filter.
class ForgeFilterPreset {
  final String name;
  final ForgeFilter filter;

  /// Whether it is one of the three that cannot be deleted.
  final bool builtIn;

  const ForgeFilterPreset(this.name, this.filter, {this.builtIn = false});

  Map<String, Object?> encode() => {'name': name, 'rules': filter.encode()};

  static ForgeFilterPreset? decode(Object? value) {
    if (value is! Map) return null;
    final name = value['name'];
    if (name is! String || name.isEmpty) return null;
    return ForgeFilterPreset(name, ForgeFilter.decode(value['rules']));
  }
}

/// The built-in presets, in the order a picker lists them.
abstract final class ForgeBuiltInPresets {
  static const allFilesName = 'All files';
  @visibleForTesting
  static const textFilesName = 'Text files';
  @visibleForTesting
  static const questFolderName = 'Tom quest folder';

  static const _allFilesRules = <ForgeFilterRule>[
    ForgeHiddenRule(show: false),
    ForgeGitignoredRule(show: false),
    ForgeTodoSiblingsRule(show: true),
  ];

  /// The extensions **Text files** shows.
  static const _textExtensions = [
    'md', 'txt', 'yaml', 'yml', 'json', 'env', 'dart', 'ts', 'js', 'sh', //
    'py', 'toml', 'ini', 'csv',
  ];

  static final allFiles = ForgeFilterPreset(
    allFilesName,
    const ForgeFilter(_allFilesRules),
    builtIn: true,
  );

  /// **All files**'s three rules come **last**: with the last match
  /// deciding, a hiding rule placed before `exclude: **` would be overridden
  /// by it, and the browser would descend into `.git`.
  @visibleForTesting
  static final textFiles = ForgeFilterPreset(
    textFilesName,
    ForgeFilter([
      ForgeGlobRule('**', include: false),
      ForgeExtensionRule(_textExtensions, include: true),
      ..._allFilesRules,
    ]),
    builtIn: true,
  );

  /// Patterns only: no folder of the workspace is named, so the preset
  /// applies to whatever root is open. The hiding rules close the list: the
  /// last match decides, so a later
  /// `include: **/*.yaml` would otherwise show the archived todo siblings
  /// again, and `exclude: **` would undo the hidden-folder rule.
  @visibleForTesting
  static final questFolder = ForgeFilterPreset(
    questFolderName,
    ForgeFilter([
      ForgeGlobRule('**', include: false),
      for (final glob in const [
        '**/overview.*.md',
        '**/quest-notes.*.md',
        '**/progress.*.md',
        '**/deferred.*.md',
        '**/open_topics.*.md',
        '**/references.*.md',
        '**/decisions.*.md',
        '**/questions.*.md',
        '**/quest_refresh.*.md',
        '**/quest_documentation_update.*.md',
        '**/*.md',
        '**/*.todo.yaml',
        '**/live-trail*.md',
        '**/*.yaml',
        '**/*.yml',
        '**/*.env',
      ])
        ForgeGlobRule(glob, include: true),
      ForgeGlobRule('**/history/**', include: false),
      const ForgeTodoSiblingsRule(show: false),
      const ForgeHiddenRule(show: false),
      const ForgeGitignoredRule(show: false),
    ]),
    builtIn: true,
  );

  static List<ForgeFilterPreset> get all => [allFiles, textFiles, questFolder];
}

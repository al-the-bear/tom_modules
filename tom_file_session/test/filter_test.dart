/// The tree filter: globs, gitignore, rules with the last match deciding,
/// the built-in presets and their persisted form.
library;

import 'package:test/test.dart';
import 'package:tom_basics/utilities.dart';
import 'package:tom_file_session/tom_file_session.dart';

ForgeFilterSubject _file(String path, {bool ignored = false}) =>
    ForgeFilterSubject(
      path: path,
      name: path.split('/').last,
      isDirectory: false,
      gitignored: ignored,
    );

ForgeFilterSubject _dir(String path, {bool ignored = false}) =>
    ForgeFilterSubject(
      path: path,
      name: path.split('/').last,
      isDirectory: true,
      gitignored: ignored,
    );

bool _shows(ForgeFilterPreset preset, ForgeFilterSubject s) =>
    preset.filter.evaluate(s).shown;

void main() {
  group('FILTER-G globs', () {
    test('FILTER-G1: * stays in a segment, ** crosses them, **/ may be '
        'empty [1011]', () {
      expect(TomGlob('*.md').matches('a.md'), isTrue);
      expect(TomGlob('*.md').matches('x/a.md'), isFalse);
      expect(TomGlob('**/*.md').matches('a.md'), isTrue);
      expect(TomGlob('**/*.md').matches('x/y/a.md'), isTrue);
      expect(TomGlob('**/history/**').matches('q/history/h.md'), isTrue);
      expect(TomGlob('**/history/**').matches('q/historyx/h.md'), isFalse);
      expect(TomGlob('**').matches('anything/at/all'), isTrue);
    });

    test('FILTER-G2: ?, {a,b} and [...] [1011]', () {
      expect(TomGlob('a?.md').matches('ab.md'), isTrue);
      expect(TomGlob('a?.md').matches('a/.md'), isFalse);
      expect(TomGlob('*.{yaml,yml}').matches('c.yml'), isTrue);
      expect(TomGlob('*.{yaml,yml}').matches('c.json'), isFalse);
      expect(TomGlob('[ab]*.md').matches('b1.md'), isTrue);
      expect(TomGlob('[!ab]*.md').matches('b1.md'), isFalse);
    });

    test('FILTER-G3: a gitignore line without a slash matches at any '
        'depth, with one it is anchored, a trailing slash is folders only, '
        'and ! re-includes [1011]', () {
      final g = TomGitignore.parse('', '''
# comment
*.log
/top.txt
build/
!keep.log
''');
      expect(g.verdict('a/b/x.log', isDirectory: false), isTrue);
      expect(g.verdict('keep.log', isDirectory: false), isFalse);
      expect(g.verdict('top.txt', isDirectory: false), isTrue);
      expect(g.verdict('a/top.txt', isDirectory: false), isNull);
      expect(g.verdict('x/build', isDirectory: true), isTrue);
      expect(g.verdict('x/build', isDirectory: false), isNull);
      final nested = TomGitignore.parse('sub', 'out/\n');
      expect(nested.verdict('sub/out', isDirectory: true), isTrue);
      expect(nested.verdict('other/out', isDirectory: true), isNull);
    });
  });

  group('FILTER-F rules', () {
    test('FILTER-F1: the last matching rule decides; no match shows '
        '[1011]', () {
      final filter = ForgeFilter([
        ForgeGlobRule('**', include: false),
        ForgeExtensionRule(['md'], include: true),
        ForgeGlobRule('drafts/**', include: false),
      ]);
      expect(filter.evaluate(_file('a.md')).shown, isTrue);
      expect(filter.evaluate(_file('a.txt')).shown, isFalse);
      expect(filter.evaluate(_file('drafts/a.md')).shown, isFalse);
      final verdict = filter.evaluate(_file('drafts/a.md'));
      expect(verdict.rule?.describe(), 'exclude: drafts/**');
      expect(const ForgeFilter([]).evaluate(_file('x')).shown, isTrue);
    });

    test('FILTER-F2: extensions never match a folder, and `.env` has the '
        'extension env [1011]', () {
      final rule = ForgeExtensionRule(['env', '.MD'], include: true);
      expect(rule.matches(_file('.env')), isTrue);
      expect(rule.matches(_file('x.env')), isTrue);
      expect(rule.matches(_file('README.md')), isTrue);
      expect(rule.matches(_dir('notes.md')), isFalse);
    });

    test('FILTER-F3: only a hidden or gitignored folder hides its '
        'subtree [1011]', () {
      final filter = ForgeFilter([
        ForgeGlobRule('**', include: false),
        const ForgeHiddenRule(show: false),
      ]);
      final dotDir = _dir('.git');
      expect(filter.hidesSubtree(dotDir, filter.evaluate(dotDir)), isTrue);
      final plain = _dir('docs');
      expect(filter.hidesSubtree(plain, filter.evaluate(plain)), isFalse);
    });

    test('FILTER-F4: a filter and a preset survive their persisted form '
        '[1011]', () {
      final filter = ForgeBuiltInPresets.questFolder.filter;
      final again = ForgeFilter.decode(filter.encode());
      expect(again.encode(), filter.encode());
      final preset = ForgeFilterPreset('Mine', filter);
      expect(
        ForgeFilterPreset.decode(preset.encode())!.encode(),
        preset.encode(),
      );
      expect(ForgeFilterRule.decode({'rule': 'nonsense'}), isNull);
    });
  });

  group('FILTER-P built-in presets', () {
    test('FILTER-P1: All files hides dot entries and gitignored ones, '
        'shows todo siblings [1011]', () {
      final all = ForgeBuiltInPresets.allFiles;
      expect(_shows(all, _file('a.png')), isTrue);
      expect(_shows(all, _file('.hidden.md')), isFalse);
      expect(_shows(all, _file('x.log', ignored: true)), isFalse);
      expect(_shows(all, _file('q/todos-archived.q.todo.yaml')), isTrue);
    });

    test('FILTER-P2: Text files shows the text extensions and still '
        'hides a dot folder [1011]', () {
      final text = ForgeBuiltInPresets.textFiles;
      expect(_shows(text, _file('a.md')), isTrue);
      expect(_shows(text, _file('a.dart')), isTrue);
      expect(_shows(text, _file('a.png')), isFalse);
      final git = _dir('.git');
      expect(text.filter.hidesSubtree(git, text.filter.evaluate(git)), isTrue);
    });

    test('FILTER-P3: the quest preset shows the quest documents, todo '
        'files, trails and configuration, and hides archived siblings, '
        'history and dot entries — even under its later includes '
        '[1011]', () {
      final quest = ForgeBuiltInPresets.questFolder;
      for (final shown in [
        'q/overview.q.md',
        'q/quest-notes.q.md',
        'q/todos.q.todo.yaml',
        'q/session-todo.mbp.q.todo.yaml',
        'q/live-trail.md',
        'q/config.yaml',
        'q/secrets.env',
      ]) {
        expect(_shows(quest, _file(shown)), isTrue, reason: shown);
      }
      for (final hidden in [
        'q/todos-archived.q.todo.yaml',
        'q/session-todo-deleted.mbp.q.todo.yaml',
        'q/history/history.md',
        'q/image.png',
        'q/notes.txt',
      ]) {
        expect(_shows(quest, _file(hidden)), isFalse, reason: hidden);
      }
      // A dot folder hides everything inside it, so the walk never reaches
      // `.hidden/inside.md` — even though `**/*.md` would show the file.
      final dot = _dir('.hidden');
      expect(
        quest.filter.hidesSubtree(dot, quest.filter.evaluate(dot)),
        isTrue,
      );
    });

    test('FILTER-P4: the quest preset names no folder — every glob '
        'starts at any depth [1011]', () {
      for (final rule in ForgeBuiltInPresets.questFolder.filter.rules) {
        if (rule is ForgeGlobRule) {
          expect(rule.glob.pattern, startsWith('**'), reason: '$rule');
        }
      }
    });
  });
}

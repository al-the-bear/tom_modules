/// A `.env` file read line by line and edited one line at a time, with
/// every other byte kept.
library;

import 'package:test/test.dart';
import 'package:tom_file_session/tom_file_session.dart';

const String envFile = '''# Database
DB_HOST=localhost
export DB_PASSWORD="s3cret pass" # rotated monthly
DB_USER='admin'
# DB_REPLICA=replica.local

# Tokens
API_TOKEN=abc123
EMPTY=
not an entry
''';

void main() {
  group('ENV-V env file', () {
    test('ENV-V1: lines are entries, commented-out entries, section '
        'comments, blanks or unreadable [1011]', () {
      final env = ForgeEnvFile.parse(envFile);
      expect(env.lines.map((l) => l.kind).toList(), [
        ForgeEnvLineKind.section,
        ForgeEnvLineKind.entry,
        ForgeEnvLineKind.entry,
        ForgeEnvLineKind.entry,
        ForgeEnvLineKind.commented,
        ForgeEnvLineKind.blank,
        ForgeEnvLineKind.section,
        ForgeEnvLineKind.entry,
        ForgeEnvLineKind.entry,
        ForgeEnvLineKind.unreadable,
      ]);
      final byKey = {for (final e in env.entries) e.key: e.value};
      expect(byKey, {
        'DB_HOST': 'localhost',
        'DB_PASSWORD': 's3cret pass',
        'DB_USER': 'admin',
        'DB_REPLICA': 'replica.local',
        'API_TOKEN': 'abc123',
        'EMPTY': '',
      });
      expect(env.unreadableLines, [10]);
      expect(env.lines.first.comment, 'Database');
    });

    test('ENV-V2: a value edit keeps quotes, export and the inline '
        'comment [1011]', () {
      final env = ForgeEnvFile.parse(envFile);
      expect(
        env.withValue(2, 'new one'),
        envFile.replaceFirst('"s3cret pass"', '"new one"'),
      );
      expect(
        env.withValue(3, 'root'),
        envFile.replaceFirst("'admin'", "'root'"),
      );
      expect(
        env.withValue(1, 'db.example'),
        envFile.replaceFirst('localhost', 'db.example'),
      );
      expect(
        env.withValue(7, 'has # hash'),
        envFile.replaceFirst('abc123', '"has # hash"'),
      );
    });

    test('ENV-V3: toggle, rename, delete and add each change one line '
        '[1011]', () {
      final env = ForgeEnvFile.parse(envFile);
      expect(
        env.withToggled(4),
        envFile.replaceFirst('# DB_REPLICA', 'DB_REPLICA'),
      );
      expect(
        env.withToggled(1),
        envFile.replaceFirst('DB_HOST=', '# DB_HOST='),
      );
      expect(
        env.withToggled(2),
        envFile.replaceFirst('export DB_PASSWORD', '# export DB_PASSWORD'),
      );
      expect(
        env.withKey(7, 'API_KEY'),
        envFile.replaceFirst('API_TOKEN', 'API_KEY'),
      );
      expect(env.withoutLine(8), envFile.replaceFirst('EMPTY=\n', ''));
      expect(env.withAdded('NEW', 'x y'), '${envFile}NEW="x y"\n');
      expect(() => env.withKey(1, '1BAD'), throwsArgumentError);
    });

    test('ENV-V4: CRLF lines are read and kept [1011]', () {
      final crlf = envFile.replaceAll('\n', '\r\n');
      final env = ForgeEnvFile.parse(crlf);
      expect(env.lines[1].value, 'localhost');
      expect(env.withValue(1, 'x'), crlf.replaceFirst('localhost', 'x'));
      expect(env.withAdded('N', 'v').endsWith('N=v\r\n'), isTrue);
    });

    test('ENV-V5: the masked text hides every value and nothing '
        'else [1011]', () {
      final masked = ForgeEnvFile.parse(envFile).masked();
      for (final secret in [
        'localhost',
        's3cret',
        'admin',
        'replica.local',
        'abc123',
      ]) {
        expect(masked, isNot(contains(secret)));
      }
      expect(masked, contains('export DB_PASSWORD=••• # rotated monthly'));
      expect(masked, contains('# DB_REPLICA=•••'));
      expect(masked, contains('EMPTY=\n'));
      expect(masked, contains('# Tokens'));
    });

    test('ENV-V6: an inline comment is read beside its entry, not into '
        'its value; a # inside quotes is value [1012]', () {
      final env = ForgeEnvFile.parse(
        'A=1  # first\nB="x # y"\n# C=3 # off\nD=plain\n',
      );
      final byKey = {for (final e in env.entries) e.key: e};
      expect(byKey['A']!.comment, 'first');
      expect(byKey['A']!.value, '1');
      expect(byKey['B']!.comment, '');
      expect(byKey['B']!.value, 'x # y');
      expect(byKey['C']!.comment, 'off');
      expect(byKey['D']!.comment, '');
    });

    test('ENV-V7: a value is written in its own quotes, plain when it '
        'needs none, else in double quotes with escapes [1012]', () {
      expect(ForgeEnvFile.encodeValue('abc', ''), 'abc');
      expect(ForgeEnvFile.encodeValue('a b', ''), '"a b"');
      expect(ForgeEnvFile.encodeValue('a#b', ''), '"a#b"');
      expect(ForgeEnvFile.encodeValue('abc', "'"), "'abc'");
      expect(ForgeEnvFile.encodeValue("it's", "'"), '"it\'s"');
      expect(ForgeEnvFile.encodeValue('say "hi"\n', '"'), r'"say \"hi\"\n"');
      expect(ForgeEnvFile.encodeValue('', ''), '');
    });
  });
}

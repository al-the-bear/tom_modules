// The private copy of tom_basics' yaml_lines.dart (lib/src/yaml_lines.dart)
// stays equal to the original. Runs where the workspace's tom_basics sits next
// to this package (the Tom workspace); a published copy alone skips it.
import 'dart:io';

import 'package:test/test.dart';

const _marker = '// ---- tom_basics/lib/src/utilities/yaml_lines.dart below, unchanged ----\n';

void main() {
  final original = File('../../tom_ai/basics/tom_basics/lib/src/utilities/yaml_lines.dart');
  test(
    'TODOMODEL-Y1: the copy of yaml_lines.dart equals tom_basics\' file [1021]',
    () {
      final copy = File('lib/src/yaml_lines.dart').readAsStringSync();
      final at = copy.indexOf(_marker);
      expect(at, isNonNegative, reason: 'the copy names where it starts');
      expect(
        copy.substring(at + _marker.length),
        original.readAsStringSync(),
        reason: 'tom_basics changed yaml_lines.dart: copy it here again, or '
            'depend on tom_basics if it is taken from pub.dev throughout now',
      );
    },
    skip: original.existsSync() ? false : 'tom_basics is not next to this package',
  );
}

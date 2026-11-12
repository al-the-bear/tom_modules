// The id pattern and the group rule of todo ids (VS Code extension quest,
// vscimpb59: groups may start with a number, which sorts them).
import 'package:test/test.dart';
import 'package:tom_todo_model/tom_todo_model.dart';

void main() {
  group('tomTodoGroupOf', () {
    test('a leading number is part of the group name', () {
      expect(tomTodoGroupOf('001_cleanup1_akki-x'), (prefix: '001_cleanup', number: 1));
      expect(tomTodoGroupOf('001_cleanup2_akki-y'), (prefix: '001_cleanup', number: 2));
      expect(tomTodoGroupOf('010_review12'), (prefix: '010_review', number: 12));
    });

    test('after it, the prefix runs to the first digit, that digit run is the number', () {
      expect(tomTodoGroupOf('ccparity_b_panels-7_akds-x'), (prefix: 'ccparity_b_panels-', number: 7));
      expect(tomTodoGroupOf('vscimpb59_akkj-numeric-leading-todo-groups'), (prefix: 'vscimpb', number: 59));
      expect(tomTodoGroupOf('csm2r1'), (prefix: 'csm', number: 2));
      expect(tomTodoGroupOf('dart313b1_akip-x'), (prefix: 'dart', number: 313));
      expect(tomTodoGroupOf('d4rt-analysis-cache'), (prefix: 'd', number: 4));
    });

    test('no number after the prefix: no group', () {
      expect(tomTodoGroupOf('aaa_cleanup'), (prefix: '', number: null));
      expect(tomTodoGroupOf('001_cleanup'), (prefix: '', number: null));
      expect(tomTodoGroupOf('0011'), (prefix: '', number: null));
      expect(tomTodoGroupOf(''), (prefix: '', number: null));
    });
  });

  group('tomTodoIdPattern', () {
    test('accepts letter-led and number-led ids', () {
      for (final id in ['vscimpb59_akkj-x', '001_cleanup1_akki-x', 'a', 'qrfix12_aklq-ä', '2026review3']) {
        expect(tomIsTodoId(id), isTrue, reason: id);
      }
    });

    test('refuses ids without a letter, a leading separator, capitals and spaces', () {
      for (final id in ['001', '_cleanup1_akki-x', '-x', 'Abc', 'a b', '']) {
        expect(tomIsTodoId(id), isFalse, reason: id);
      }
    });
  });
}

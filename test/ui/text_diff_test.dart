import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/ui/text_diff.dart';

void main() {
  test('appending_inserts_only_the_new_text', () {
    final d = diffText('ab', 'abc');
    expect((d.deleted, d.inserted), (0, 'c'));
  });

  test('removing_the_last_character_deletes_one', () {
    final d = diffText('abc', 'ab');
    expect((d.deleted, d.inserted), (1, ''));
  });

  test('editing_in_the_middle_replaces_from_the_change', () {
    final d = diffText('abc', 'axc');
    expect((d.deleted, d.inserted), (2, 'xc'));
  });

  test('clearing_deletes_everything', () {
    final d = diffText('abc', '');
    expect((d.deleted, d.inserted), (3, ''));
  });

  test('no_change_does_nothing', () {
    final d = diffText('abc', 'abc');
    expect((d.deleted, d.inserted), (0, ''));
  });

  test('emoji_count_as_one_character', () {
    final d = diffText('a😀', 'a');
    expect((d.deleted, d.inserted), (1, ''));
  });
}

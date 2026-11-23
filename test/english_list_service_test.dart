import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/features/import/data/english_list_service.dart';

void main() {
  test('built-in English lists are gloss-only and not empty', () {
    for (final list in englishBuiltInLists) {
      final raw = File(list.asset).readAsStringSync();
      final drafts = draftsFromEnglishList(raw);
      expect(drafts.length, greaterThan(100), reason: list.id);
      expect(drafts.first.korean.trim(), isNotEmpty);
      expect(drafts.first.meaningZh.trim(), isNotEmpty);
      expect(raw.contains('ECDICT'), isTrue);
    }
  });
}

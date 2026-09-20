import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/core/database/app_database.dart';
import 'package:korean_memo/features/import/data/excel_import_service.dart';
import 'package:korean_memo/features/import/domain/import_models.dart';

void main() {
  group('ExcelImportService', () {
    test('recognizes Korean and Chinese header aliases', () {
      final mapping = ExcelImportService().guessMapping(
        const ['단어', '뜻', '품사', '예문'],
      );

      expect(mapping[ImportField.korean], 0);
      expect(mapping[ImportField.meaningZh], 1);
      expect(mapping[ImportField.partOfSpeech], 2);
      expect(mapping[ImportField.exampleKo], 3);
    });

    test('normalizes lookup whitespace without changing Hangul', () {
      expect(normalizeLookup('  안녕　 하세요  '), '안녕 하세요');
    });
  });
}

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/features/import/data/csv_import_service.dart';

void main() {
  for (final delimiter in [',', '\t']) {
    for (final bom in [false, true]) {
      test(
        'UTF-8 import handles Chinese headers and content ($delimiter, BOM $bom)',
        () {
          final text =
              '${bom ? '\uFEFF' : ''}${['词头', '中文', '例句中文'].join(delimiter)}\n'
              '${['sky', '天空', '天空是蓝色的'].join(delimiter)}';
          final result = CsvImportService().parseBytes(utf8.encode(text));
          expect(result.drafts.single.meaningZh, '天空');
          expect(result.drafts.single.exampleZh, '天空是蓝色的');
        },
      );
    }
  }
  test(
    'invalid UTF-8 gives actionable error and oversized file is rejected',
    () {
      expect(
        () => CsvImportService().parseBytes([0xff]),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('UTF-8'),
          ),
        ),
      );
      expect(
        () =>
            CsvImportService().parseBytes(List.filled(2 * 1024 * 1024 + 1, 65)),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('2MB'),
          ),
        ),
      );
    },
  );
  test('English CSV keeps IPA, part of speech and examples', () {
    const csv =
        '词头,中文,IPA,词性,例句,例句中文\n'
        'sky,天,skaɪ,名词,"The sky is blue.",天空是蓝的\n'
        ',缺词头,x,名词,,\n';
    final parsed = CsvImportService().parse(csv);
    expect(parsed.invalidRows, 1);
    expect(parsed.drafts, hasLength(1));
    expect(parsed.drafts.single.korean, 'sky');
    expect(parsed.drafts.single.meaningZh, '天');
    expect(parsed.drafts.single.ipa, 'skaɪ');
    expect(parsed.drafts.single.partOfSpeech, '名词');
    expect(parsed.drafts.single.exampleKo, 'The sky is blue.');
    expect(parsed.drafts.single.exampleZh, '天空是蓝的');
  });
}

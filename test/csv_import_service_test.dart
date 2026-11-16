import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/features/import/data/csv_import_service.dart';

void main() {
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

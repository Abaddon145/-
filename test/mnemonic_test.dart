import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/core/database/app_database.dart';
import 'package:korean_memo/features/ai/domain/mnemonic.dart';

Word sample(String language) => Word(
  id: 7,
  headword: language == 'en' ? 'preview' : '시험',
  normalizedHeadword: language == 'en' ? 'preview' : '시험',
  baseForm: '',
  normalizedBaseForm: '',
  meaningZh: language == 'en' ? '预习' : '考试',
  language: language,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

void main() {
  test('mnemonic cache keys and prompts stay in their language', () {
    final english = sample('en');
    final korean = sample('ko');
    expect(mnemonicCacheKey(english), 'mnemonic:en:7');
    expect(mnemonicCacheKey(korean), 'mnemonic:ko:7');
    expect(mnemonicPrompt(english), contains('词根'));
    expect(mnemonicPrompt(english), isNot(contains('韩文例句')));
    expect(mnemonicPrompt(korean), contains('活用'));
  });
}

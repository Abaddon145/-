import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/core/database/app_database.dart';
import 'package:korean_memo/features/study/domain/practice.dart';
import 'package:korean_memo/services/tts_service.dart';

void main() {
  Word englishWord() => Word(
    id: 1,
    headword: 'Sky',
    normalizedHeadword: 'sky',
    baseForm: '',
    normalizedBaseForm: '',
    meaningZh: '天空',
    language: 'en',
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );

  test('English spelling and dictation ask for the headword', () {
    final word = englishWord();
    for (final mode in [PracticeMode.spelling, PracticeMode.listening]) {
      final item = practiceItem(
        word,
        SessionOptions(mode: mode, language: 'en'),
      );
      expect(item.answer, 'Sky');
      expect(item.spoken, 'Sky');
      expect(answerMatches('  sky ', item.answer), isTrue);
      expect(answerMatches('SKY', item.answer), isTrue);
      final speech = speechRequest(item.spoken, learningLanguage: 'en');
      expect(speech.language, 'en-US');
      expect(speech.spoken, 'Sky');
    }
  });
}

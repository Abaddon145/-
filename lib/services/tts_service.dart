import 'package:flutter_tts/flutter_tts.dart';

import '../core/language/learning_language.dart';

final hangulPattern = RegExp(r'[가-힣ㄱ-ㅎㅏ-ㅣ]');

({String language, String spoken}) speechRequest(
  String text, {
  String learningLanguage = 'ko',
  String englishAccent = 'en-US',
}) {
  if (normalizeLearningLanguage(learningLanguage) == 'en') {
    return (
      language: englishAccent == 'en-GB' ? 'en-GB' : 'en-US',
      spoken: text.trim(),
    );
  }
  final hasKorean = hangulPattern.hasMatch(text);
  final spoken = hasKorean
      ? text.split('/').where(hangulPattern.hasMatch).join(' ').trim()
      : text;
  return (language: hasKorean ? 'ko-KR' : 'en-US', spoken: spoken);
}

class TtsService {
  TtsService() : _tts = FlutterTts();

  final FlutterTts _tts;

  Future<void> speakKorean(
    String text, {
    double rate = .45,
    String learningLanguage = 'ko',
    String englishAccent = 'en-US',
  }) async {
    await _tts.stop();
    final request = speechRequest(
      text,
      learningLanguage: learningLanguage,
      englishAccent: englishAccent,
    );
    await _tts.setLanguage(request.language);
    if (request.language.startsWith('en')) {
      await _useEnglishVoice(request.language);
    }
    await _tts.setSpeechRate(rate.clamp(.2, .8));
    await _tts.awaitSpeakCompletion(true);
    await _tts.speak(request.spoken);
  }

  Future<void> _useEnglishVoice(String locale) async {
    try {
      final voices = await _tts.getVoices;
      if (voices is! List) return;
      Map? chosen;
      final wanted = locale.toLowerCase();
      for (final voice in voices) {
        if (voice is! Map) continue;
        final voiceLocale = '${voice['locale'] ?? voice['lang'] ?? ''}'
            .toLowerCase()
            .replaceAll('_', '-');
        if (voiceLocale.startsWith(wanted)) {
          chosen = voice;
          break;
        }
        if (chosen == null && voiceLocale.startsWith('en')) chosen = voice;
      }
      if (chosen == null) return;
      await _tts.setVoice({
        'name': '${chosen['name'] ?? ''}',
        'locale': '${chosen['locale'] ?? chosen['lang'] ?? locale}',
      });
    } catch (_) {
      // The language is already en-US. A missing voice list should not block speech.
    }
  }

  Future<void> dispose() => _tts.stop();
}

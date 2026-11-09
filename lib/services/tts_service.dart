import 'package:flutter_tts/flutter_tts.dart';

final hangulPattern = RegExp(r'[가-힣ㄱ-ㅎㅏ-ㅣ]');

({String language, String spoken}) speechRequest(String text) {
  final hasKorean = hangulPattern.hasMatch(text);
  final spoken = hasKorean
      ? text.split('/').where(hangulPattern.hasMatch).join(' ').trim()
      : text;
  return (language: hasKorean ? 'ko-KR' : 'en-US', spoken: spoken);
}

class TtsService {
  TtsService() : _tts = FlutterTts();

  final FlutterTts _tts;

  Future<void> speakKorean(String text, {double rate = .45}) async {
    await _tts.stop();
    final request = speechRequest(text);
    await _tts.setLanguage(request.language);
    await _tts.setSpeechRate(rate.clamp(.2,.8));
    await _tts.awaitSpeakCompletion(true);
    await _tts.speak(request.spoken);
  }

  Future<void> dispose() => _tts.stop();
}

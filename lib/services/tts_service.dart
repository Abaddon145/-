import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  TtsService() : _tts = FlutterTts();

  final FlutterTts _tts;

  Future<void> speakKorean(String text) async {
    await _tts.stop();
    final hasKorean = RegExp(r'[가-힣ㄱ-ㅎㅏ-ㅣ]').hasMatch(text);
    final spoken = hasKorean
        ? text.split('/').where((part) => RegExp(r'[가-힣ㄱ-ㅎㅏ-ㅣ]').hasMatch(part)).join(' ').trim()
        : text;
    await _tts.setLanguage(hasKorean ? 'ko-KR' : 'en-US');
    await _tts.setSpeechRate(0.45);
    await _tts.awaitSpeakCompletion(true);
    await _tts.speak(spoken);
  }

  Future<void> dispose() => _tts.stop();
}

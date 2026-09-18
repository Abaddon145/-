import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  TtsService() : _tts = FlutterTts();

  final FlutterTts _tts;

  Future<void> speakKorean(String text) async {
    await _tts.stop();
    await _tts.setLanguage('ko-KR');
    await _tts.setSpeechRate(0.45);
    await _tts.awaitSpeakCompletion(true);
    await _tts.speak(text);
  }

  Future<void> dispose() => _tts.stop();
}

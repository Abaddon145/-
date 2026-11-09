import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/services/tts_service.dart';

void main() {
  test('Korean phrases are spoken in Korean and English terms stay in English', () {
    final korean = speechRequest('love / 사랑');
    expect(korean.language, 'ko-KR');
    expect(korean.spoken, '사랑');
    final english = speechRequest('warehouse');
    expect(english.language, 'en-US');
    expect(english.spoken, 'warehouse');
  });
}

import 'package:flutter/widgets.dart';

class TypingMeter {
  int correctChars = 0;
  int typedChars = 0;
  int elapsedMs = 0;

  void commit({
    required String typed,
    required String expected,
    required int elapsedMs,
  }) {
    final typedMarks = typed.characters.toList();
    final expectedMarks = expected.characters.toList();
    var correct = 0;
    for (var index = 0; index < typedMarks.length; index++) {
      if (index < expectedMarks.length &&
          typedMarks[index] == expectedMarks[index]) {
        correct += 1;
      }
    }
    typedChars += typedMarks.length;
    correctChars += correct;
    this.elapsedMs += elapsedMs < 0 ? 0 : elapsedMs;
  }

  /// One word is five correct characters.
  double get wpm => elapsedMs <= 0 ? 0 : correctChars / 5 / (elapsedMs / 60000);

  double get accuracy => typedChars == 0 ? 1 : correctChars / typedChars;
}

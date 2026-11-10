import 'dart:convert';

/// In-progress answer kept across a lock screen if iOS relaunches the process.
class StudyDraft {
  const StudyDraft({
    required this.wordId,
    required this.sessionKey,
    required this.answer,
    required this.revealed,
    this.correct,
  });

  static const storageKey = 'study_input_draft';

  final int wordId;
  final String sessionKey;
  final String answer;
  final bool revealed;
  final bool? correct;

  String encode() => jsonEncode({
    'wordId': wordId,
    'sessionKey': sessionKey,
    'answer': answer,
    'revealed': revealed,
    'correct': correct,
  });

  static StudyDraft? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return null;
      final wordId = data['wordId'];
      final sessionKey = data['sessionKey'];
      final answer = data['answer'];
      if (wordId is! int || sessionKey is! String || answer is! String) {
        return null;
      }
      final correct = data['correct'];
      return StudyDraft(
        wordId: wordId,
        sessionKey: sessionKey,
        answer: answer,
        revealed: data['revealed'] == true,
        correct: correct is bool ? correct : null,
      );
    } catch (_) {
      return null;
    }
  }
}

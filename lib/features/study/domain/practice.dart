import '../../../core/database/app_database.dart';
import '../../../core/database/missing_meaning.dart';
import '../../../core/text/cloze_target.dart';

class PracticeItem {
  const PracticeItem(this.question, this.answer, this.spoken);
  final String question;
  final String answer;
  final String spoken;
}

PracticeItem practiceItem(Word word, SessionOptions options, {String forms = '', int formIndex = 0}) {
  final parts = word.korean.split('/').map((s) => s.trim()).toList();
  final ko = parts.where((s) => RegExp(r'[가-힣ㄱ-ㅎㅏ-ㅣ]').hasMatch(s)).join(' / ');
  final en = parts.where((s) => RegExp(r'[a-zA-Z]').hasMatch(s) && !RegExp(r'[가-힣]').hasMatch(s)).join(' / ');
  final translated = !isMissingMeaning(word.meaningZh);
  final front = ko.isNotEmpty ? ko : word.korean;
  final back = translated ? word.meaningZh : en.isNotEmpty && ko.isNotEmpty ? en : '暂无翻译，请在编辑中补充';
  if (options.mode == PracticeMode.cloze) {
    final target = clozeTarget(word.korean);
    return PracticeItem((word.exampleKo ?? '').replaceAll(target, '＿＿＿'), target, word.exampleKo ?? target);
  }
  if (options.mode == PracticeMode.forms) {
    final lines=forms.split('\n').where((s)=>s.contains('=')).toList();
    final line = lines.isEmpty ? '活用=$front' : lines[formIndex % lines.length];
    return PracticeItem('$front · ${line.split('=').first.trim()}', line.substring(line.indexOf('=') + 1).trim(), front);
  }
  if (options.mode == PracticeMode.spelling || options.mode == PracticeMode.listening) {
    final answer = options.direction == StudyDirection.reverse && en.isNotEmpty && ko.isNotEmpty ? en : front;
    return PracticeItem(options.mode == PracticeMode.listening ? '听发音，输入单词' : back, answer, answer);
  }
  return options.direction == StudyDirection.forward
    ? PracticeItem(front, back, front) : PracticeItem(back, front, front);
}

String normalizeAnswer(String value) => value.toLowerCase().replaceAll(RegExp(r'[\s.,!?，。！？·;；]'), '').trim();
bool answerMatches(String input, String expected) => expected.split(RegExp(r'[/；;]'))
  .any((part) => normalizeAnswer(part) == normalizeAnswer(input));

class AnswerMark {
  const AnswerMark(this.text, this.match);
  final String text;
  final bool match;
}

class AnswerDiff {
  const AnswerDiff(this.input, this.expected);
  final List<AnswerMark> input;
  final List<AnswerMark> expected;
}

/// Aligns graphemes so a shorter or shifted answer is not colored by raw index.
/// This does not decide whether the answer is correct.
List<String> _answerUnits(String value) =>
    value.runes.map(String.fromCharCode).toList();

AnswerDiff diffAnswer(String input, String expected) {
  final a = _answerUnits(input);
  final b = _answerUnits(expected);
  final rows = a.length + 1;
  final cols = b.length + 1;
  final dp = List.generate(rows, (_) => List<int>.filled(cols, 0));
  for (var i = a.length - 1; i >= 0; i--) {
    for (var j = b.length - 1; j >= 0; j--) {
      dp[i][j] = a[i] == b[j]
          ? dp[i + 1][j + 1] + 1
          : (dp[i + 1][j] > dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
    }
  }
  final inputMarks = <AnswerMark>[];
  final expectedMarks = <AnswerMark>[];
  var i = 0, j = 0;
  while (i < a.length && j < b.length) {
    if (a[i] == b[j]) {
      inputMarks.add(AnswerMark(a[i], true));
      expectedMarks.add(AnswerMark(b[j], true));
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      inputMarks.add(AnswerMark(a[i], false));
      i++;
    } else {
      expectedMarks.add(AnswerMark(b[j], false));
      j++;
    }
  }
  while (i < a.length) {
    inputMarks.add(AnswerMark(a[i], false));
    i++;
  }
  while (j < b.length) {
    expectedMarks.add(AnswerMark(b[j], false));
    j++;
  }
  return AnswerDiff(inputMarks, expectedMarks);
}

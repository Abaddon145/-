import '../../../core/database/app_database.dart';

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
  final translated = word.meaningZh.isNotEmpty && !word.meaningZh.contains('未提供中文') && !word.meaningZh.contains('暂无中文');
  final front = ko.isNotEmpty ? ko : word.korean;
  final back = translated ? word.meaningZh : en.isNotEmpty && ko.isNotEmpty ? en : '暂无翻译，请在编辑中补充';
  if (options.mode == PracticeMode.cloze) {
    final target=front.split('/').first.trim();
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

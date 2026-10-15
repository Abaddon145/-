import 'package:korean_memo/features/ai/data/ai_key_store.dart';
import 'package:korean_memo/core/database/app_database.dart';
import 'package:korean_memo/features/ai/domain/ai_models.dart';

Future<Word> addAiWord(
  AppDatabase db,
  String term, {
  String meaning = '（待补中文）',
}) async {
  final book = await db.createWordBook(
    name: 'AI 测试',
    sourceFileName: 'unit-test',
  );
  await db.importWords(
    wordBookId: book,
    source: 'unit-test-original-source',
    drafts: [WordDraft(korean: term, meaningZh: meaning)],
  );
  return (await db.searchLibraryWords(
    query: term,
    filter: LibraryFilter.all,
  )).firstWhere((r) => r.word.korean == term).word;
}

AiSuggestion suggestionFor(
  AiRequest r, {
  Map<String, dynamic> changes = const {},
}) => AiSuggestion.fromJson({
  'result': {
    'requestId': r.requestId,
    'wordId': r.word.id,
    'originalTerm': r.word.korean,
    'context': r.context,
    'meaningZh': '测试释义',
    'partOfSpeech': '名词',
    'baseForm': '',
    'collocations': ['测试搭配'],
    'exampleKo': '시험을 봐요.',
    'exampleZh': '参加考试。',
    'workExampleKo': '작업을 확인해요.',
    'workExampleZh': '确认工作。',
    'usageNote': '测试用法',
    'grammarNote': '测试语法',
    'ambiguityNotes': [],
    'confusingWords': [],
    'terminologyNote': '',
    'suspectedTypo': false,
    'suggestedSpellings': [],
    'needsMoreContext': false,
    ...changes,
  },
  'model': 'unit-test-model',
  'generatedAt': '2026-10-14T01:02:03Z',
  'promptVersion': aiPromptVersion,
});

class TestAiKeyStore implements AiKeyStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String key) async {
    value = key;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

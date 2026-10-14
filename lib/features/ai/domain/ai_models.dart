import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/missing_meaning.dart';

import 'ai_response.dart';
export 'ai_response.dart';

/// Content and normalized instants avoid local/UTC equality and same-second edits.
Map<String, Object?> aiWordSnapshot(Word word) => {
  'wordId': word.id,
  'originalTerm': word.korean,
  'meaningZh': word.meaningZh,
  'partOfSpeech': word.partOfSpeech ?? '',
  'baseForm': word.baseForm,
  'exampleKo': word.exampleKo ?? '',
  'exampleZh': word.exampleZh ?? '',
  'pronunciation': word.pronunciation,
  'tags': word.tags,
  'note': word.note,
  'source': word.source,
  'category': word.category,
  'hanja': word.hanja,
  'etymology': word.etymology,
  'topikLevel': word.topikLevel,
  'createdAt': word.createdAt.millisecondsSinceEpoch ~/ 1000,
  'updatedAt': word.updatedAt.millisecondsSinceEpoch ~/ 1000,
};
String aiSnapshotJson(Word word) => jsonEncode(aiWordSnapshot(word));
String aiCacheKey(
  Word word,
  String context,
  String type,
  String style,
  int count,
) => sha256
    .convert(
      utf8.encode(
        jsonEncode([
          aiWordSnapshot(word),
          context,
          type,
          style,
          count,
          aiPromptVersion,
        ]),
      ),
    )
    .toString();

class AiRequest implements AiRequestIdentity {
  const AiRequest({
    required this.requestId,
    required this.word,
    required this.context,
    required this.type,
    this.style = 'default',
    this.exampleCount = 1,
  });
  @override
  final String requestId;
  @override
  final String context;
  final String type, style;
  final Word word;
  @override
  int get wordId => word.id;
  @override
  String get originalTerm => word.korean;
  final int exampleCount;
  Map<String, Object?> toJson() => {
    'requestId': requestId,
    'wordId': word.id,
    'originalTerm': word.korean,
    'context': context,
    'meaningZh': word.meaningZh,
    'partOfSpeech': word.partOfSpeech ?? '',
    'baseForm': word.baseForm,
    'exampleKo': word.exampleKo ?? '',
    'exampleZh': word.exampleZh ?? '',
    'style': style,
    'exampleCount': exampleCount,
  };
  void validate() {
    if (word.korean.isEmpty ||
        word.korean.length > 200 ||
        context.isEmpty ||
        context.length > 600 ||
        word.meaningZh.length > 2000 ||
        (word.partOfSpeech?.length ?? 0) > 200 ||
        word.baseForm.length > 200 ||
        (word.exampleKo?.length ?? 0) > 1000 ||
        (word.exampleZh?.length ?? 0) > 1000 ||
        !['complete', 'explain'].contains(type) ||
        ![
          'default',
          'simpler',
          'work',
          'confusing',
          'example',
        ].contains(style) ||
        exampleCount < 1 ||
        exampleCount > 3 ||
        utf8.encode(jsonEncode(toJson())).length > 16384) {
      throw const AiException('request_too_large');
    }
  }
}

bool aiFieldMissing(String key, String? existing) => key == 'meaningZh'
    ? isMissingMeaning(existing)
    : (existing ?? '').trim().isEmpty;

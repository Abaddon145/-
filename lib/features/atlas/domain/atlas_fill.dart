import 'dart:convert';

import '../domain/atlas_models.dart';

const atlasFillFields = {
  'senses': '义项（词性、中文、英文）',
  'examples': '两条例句',
  'collocations': '搭配',
  'family': '词族',
  'synonyms': '近义',
  'antonyms': '反义',
  'tip': '用法提示',
  'cefr': 'CEFR',
  'topic': '话题',
  'usageNote': '补充说明',
};

String atlasFillPrompt({
  required String headword,
  required String language,
  required String meaning,
}) {
  final sentence = language == 'ko'
      ? 'examples 用韩文例句，字段 en 写韩文，zh 写中文，并在 senses.en 给简短英文释义。'
      : 'examples 用英文例句，en 为英文，zh 为中文。';
  return jsonEncode({
    'task': '按图鉴结构补全这个词，供用户预览、编辑和勾选后再保存。不要改写词头，不要覆盖用户已有内容，不要给出记忆评分。',
    'headword': headword,
    'language': language,
    'existingMeaning': meaning,
    'rules': [sentence, '不确定就留空，不要编造词典出处或官方词表。', '只输出 JSON。'],
    'output': {
      'senses': [
        {'pos': '', 'zh': '', 'en': ''},
      ],
      'examples': [
        {'en': '', 'zh': ''},
        {'en': '', 'zh': ''},
      ],
      'collocations': [''],
      'family': [''],
      'synonyms': [''],
      'antonyms': [''],
      'tip': '',
      'cefr': 'A1|A2|B1|B2|C1|C2|',
      'topic': '',
      'usageNote': '',
    },
  });
}

AtlasEntryDraft? parseAtlasFill(String content, {required String headword}) {
  final decoded = jsonDecode(content);
  if (decoded is! Map) return null;
  final draft = parseAtlasEntry({
    ...decoded,
    'id': 'local',
    'w': headword,
    'ex': decoded['examples'] ?? decoded['ex'],
    'col': decoded['collocations'] ?? decoded['col'],
    'fam': decoded['family'] ?? decoded['fam'],
    'syn': decoded['synonyms'] ?? decoded['syn'],
    'ant': decoded['antonyms'] ?? decoded['ant'],
    'note': decoded['usageNote'] ?? decoded['note'],
  });
  if (draft == null) return null;
  final cefr = atlasCefrLevels.contains(draft.cefr) ? draft.cefr : '';
  final topic = atlasTopics.any((item) => item.$1 == draft.topic)
      ? draft.topic
      : '';
  return AtlasEntryDraft(
    id: 'local',
    word: headword,
    ipaUk: draft.ipaUk,
    ipaUs: draft.ipaUs,
    senses: draft.senses,
    examples: draft.examples.take(2).toList(),
    collocations: draft.collocations,
    family: draft.family,
    synonyms: draft.synonyms,
    antonyms: draft.antonyms,
    tip: draft.tip,
    cefr: cefr,
    topic: topic,
    mediaFlags: 0,
    usageNote: draft.usageNote,
  );
}

/// Fields the user may save. Non-empty stored values are omitted so a save
/// cannot replace them.
Set<String> fillableAtlasFields(AtlasRecord? current) {
  if (current == null) return atlasFillFields.keys.toSet();
  return {
    if (current.senses.isEmpty) 'senses',
    if (current.examples.isEmpty) 'examples',
    if (current.collocations.isEmpty) 'collocations',
    if (current.family.isEmpty) 'family',
    if (current.synonyms.isEmpty) 'synonyms',
    if (current.antonyms.isEmpty) 'antonyms',
    if (atlasFieldBlank(current.tip)) 'tip',
    if (atlasFieldBlank(current.cefr)) 'cefr',
    if (atlasFieldBlank(current.topic)) 'topic',
    if (atlasFieldBlank(current.usageNote)) 'usageNote',
  };
}

import 'dart:convert';

/// Public Word Atlas text. Media files stay at [atlasPublicBase] and are
/// never bundled or written into backups.
const atlasPublicBase =
    'https://raw.githubusercontent.com/designfuchen/word-atlas/main/public/atlas';

const atlasBookStableId = 'word-atlas';
const atlasBookSource = 'atlas://word-atlas';
const atlasBookTitle = '词光图鉴';
const atlasWordCount = 7298;

const atlasAttribution = 'Word Atlas contributors — CC BY 4.0';
const atlasDisclaimer = '内容由 AI 生成，未逐条人工审校，不是官方雅思词表。词忆不使用词光的品牌标识或开屏动画。';

const atlasTopics = <(String, String)>[
  ('education', '教育'),
  ('work', '职场'),
  ('technology', '科技'),
  ('science', '科学'),
  ('environment', '环境'),
  ('health', '健康'),
  ('society', '社会'),
  ('government', '政法'),
  ('economy', '经济'),
  ('media', '媒体'),
  ('arts', '艺术'),
  ('travel', '旅行'),
  ('city', '城市'),
  ('nature', '自然'),
  ('daily', '生活'),
  ('emotion', '情感'),
  ('thinking', '思维'),
  ('sport', '运动'),
  ('history', '历史'),
];

const atlasCefrLevels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

const atlasMediaImage = 1;
const atlasMediaUk = 2;
const atlasMediaUs = 4;
const atlasMediaExample = 8;

const englishAccentKey = 'english_accent';
const uiSoundsKey = 'ui_sounds';
const atlasCacheMaxBytes = 80 * 1024 * 1024;
const masteredStabilityDays = 21;

String topicLabel(String? code) {
  for (final topic in atlasTopics) {
    if (topic.$1 == code) return topic.$2;
  }
  return code ?? '';
}

String normalizeEnglishAccent(String? raw) =>
    raw == 'en-GB' ? 'en-GB' : 'en-US';

bool isMasteredState({required int state, required double stability}) =>
    state == 2 && stability >= masteredStabilityDays;

class AtlasSense {
  const AtlasSense({required this.pos, required this.zh, required this.en});
  final String pos;
  final String zh;
  final String en;

  Map<String, String> toJson() => {'pos': pos, 'zh': zh, 'en': en};
}

class AtlasExample {
  const AtlasExample({required this.en, required this.zh});
  final String en;
  final String zh;

  Map<String, String> toJson() => {'en': en, 'zh': zh};
}

class AtlasEntryDraft {
  const AtlasEntryDraft({
    required this.id,
    required this.word,
    required this.ipaUk,
    required this.ipaUs,
    required this.senses,
    required this.examples,
    required this.collocations,
    required this.family,
    required this.synonyms,
    required this.antonyms,
    required this.tip,
    required this.cefr,
    required this.topic,
    required this.mediaFlags,
    required this.usageNote,
  });

  final String id;
  final String word;
  final String ipaUk;
  final String ipaUs;
  final List<AtlasSense> senses;
  final List<AtlasExample> examples;
  final List<String> collocations;
  final List<String> family;
  final List<String> synonyms;
  final List<String> antonyms;
  final String tip;
  final String cefr;
  final String topic;
  final int mediaFlags;
  final String usageNote;

  String get primaryZh => senses.isEmpty ? '' : senses.first.zh;
  String get primaryPos => senses.isEmpty ? '' : senses.first.pos;
  bool get hasImage => (atlasMediaImage & mediaFlags) != 0;
  bool get hasUk => (atlasMediaUk & mediaFlags) != 0;
  bool get hasUs => (atlasMediaUs & mediaFlags) != 0;
  bool get hasExampleAudio => (atlasMediaExample & mediaFlags) != 0;
}

class AtlasRecord {
  const AtlasRecord({
    required this.wordId,
    required this.atlasId,
    required this.ipaUk,
    required this.ipaUs,
    required this.senses,
    required this.examples,
    required this.collocations,
    required this.family,
    required this.synonyms,
    required this.antonyms,
    required this.tip,
    required this.cefr,
    required this.topic,
    required this.mediaFlags,
    required this.usageNote,
  });

  final int wordId;
  final String atlasId;
  final String ipaUk;
  final String ipaUs;
  final List<AtlasSense> senses;
  final List<AtlasExample> examples;
  final List<String> collocations;
  final List<String> family;
  final List<String> synonyms;
  final List<String> antonyms;
  final String tip;
  final String cefr;
  final String topic;
  final int mediaFlags;
  final String usageNote;

  bool get hasImage => (atlasMediaImage & mediaFlags) != 0;
}

class AtlasIndex {
  const AtlasIndex({
    required this.count,
    required this.chunk,
    required this.words,
  });
  final int count;
  final int chunk;
  final List<AtlasIndexRow> words;
  int get chunks => chunk <= 0 ? 0 : (count / chunk).ceil();
}

class AtlasIndexRow {
  const AtlasIndexRow({
    required this.id,
    required this.word,
    required this.gloss,
    required this.ipa,
    required this.cefrIndex,
    required this.topicIndex,
    required this.media,
  });
  final String id;
  final String word;
  final String gloss;
  final String ipa;
  final int cefrIndex;
  final int topicIndex;
  final int media;
}

bool atlasFieldBlank(String? value) {
  final text = (value ?? '').trim();
  return text.isEmpty || text == '[]' || text == 'null';
}

String fillBlank(String? current, String incoming) =>
    atlasFieldBlank(current) ? incoming.trim() : current!.trim();

List<String> _strings(Object? raw) => [
  for (final item in raw is List ? raw : const [])
    if (item != null && '$item'.trim().isNotEmpty) '$item'.trim(),
];

AtlasEntryDraft? parseAtlasEntry(Object? raw) {
  if (raw is! Map) return null;
  final word = '${raw['w'] ?? raw['word'] ?? ''}'.trim();
  final id = '${raw['id'] ?? ''}'.trim();
  if (word.isEmpty || id.isEmpty) return null;
  final senses = <AtlasSense>[
    for (final item in raw['senses'] is List ? raw['senses'] as List : const [])
      if (item is Map)
        AtlasSense(
          pos: '${item['pos'] ?? ''}'.trim(),
          zh: '${item['zh'] ?? ''}'.trim(),
          en: '${item['en'] ?? ''}'.trim(),
        ),
  ].where((sense) => sense.zh.isNotEmpty || sense.en.isNotEmpty).toList();
  final examples = <AtlasExample>[
    for (final item
        in raw['ex'] is List
            ? raw['ex'] as List
            : raw['examples'] is List
            ? raw['examples'] as List
            : const [])
      if (item is Map)
        AtlasExample(
          en: '${item['en'] ?? item['ko'] ?? ''}'.trim(),
          zh: '${item['zh'] ?? ''}'.trim(),
        ),
  ].where((example) => example.en.isNotEmpty).take(2).toList();
  final media = raw['m'] ?? raw['media'];
  return AtlasEntryDraft(
    id: id,
    word: word,
    ipaUk: '${raw['uk'] ?? ''}'.trim(),
    ipaUs: '${raw['us'] ?? ''}'.trim(),
    senses: senses,
    examples: examples,
    collocations: _strings(raw['col'] ?? raw['collocations']),
    family: _strings(raw['fam'] ?? raw['family']),
    synonyms: _strings(raw['syn'] ?? raw['synonyms']),
    antonyms: _strings(raw['ant'] ?? raw['antonyms']),
    tip: '${raw['tip'] ?? ''}'.trim(),
    cefr: '${raw['cefr'] ?? ''}'.trim().toUpperCase(),
    topic: '${raw['topic'] ?? ''}'.trim(),
    mediaFlags: media is int ? media : int.tryParse('$media') ?? 0,
    usageNote: '${raw['note'] ?? raw['usageNote'] ?? ''}'.trim(),
  );
}

List<AtlasEntryDraft> parseAtlasChunk(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw) parseAtlasEntry(item),
  ].whereType<AtlasEntryDraft>().toList();
}

AtlasIndex parseAtlasIndex(Object? raw) {
  if (raw is! Map) throw const FormatException('图鉴索引无效');
  final words = raw['words'];
  if (words is! List) throw const FormatException('图鉴索引无效');
  final rows = <AtlasIndexRow>[];
  for (final item in words) {
    if (item is! List || item.length < 7) continue;
    rows.add(
      AtlasIndexRow(
        id: '${item[0]}',
        word: '${item[1]}',
        gloss: '${item[2]}',
        ipa: '${item[3]}',
        cefrIndex: item[4] is int
            ? item[4] as int
            : int.tryParse('${item[4]}') ?? 0,
        topicIndex: item[5] is int
            ? item[5] as int
            : int.tryParse('${item[5]}') ?? 0,
        media: item[6] is int
            ? item[6] as int
            : int.tryParse('${item[6]}') ?? 0,
      ),
    );
  }
  final count = raw['count'] is int ? raw['count'] as int : rows.length;
  final chunk = raw['chunk'] is int ? raw['chunk'] as int : 100;
  return AtlasIndex(count: count, chunk: chunk, words: rows);
}

String atlasAssetUrl(String kind, String id) {
  final safe = id.trim();
  return switch (kind) {
    'img' => '$atlasPublicBase/img/$safe.webp',
    'thumb' => '$atlasPublicBase/thumb/$safe.webp',
    'uk' => '$atlasPublicBase/audio/uk/$safe.mp3',
    'us' => '$atlasPublicBase/audio/us/$safe.mp3',
    'ex' => '$atlasPublicBase/audio/ex/$safe.mp3',
    'index' => '$atlasPublicBase/index.json',
    _ => '$atlasPublicBase/entries/$safe.json',
  };
}

String? preferredWordAudioUrl({
  required String atlasId,
  required int mediaFlags,
  required String accent,
}) {
  if (atlasId.isEmpty) return null;
  if (accent == 'en-GB' && (atlasMediaUk & mediaFlags) != 0) {
    return atlasAssetUrl('uk', atlasId);
  }
  if ((atlasMediaUs & mediaFlags) != 0) return atlasAssetUrl('us', atlasId);
  if ((atlasMediaUk & mediaFlags) != 0) return atlasAssetUrl('uk', atlasId);
  return null;
}

String encodeAtlasList(List<Object> values) => jsonEncode(values);

List<AtlasSense> decodeSenses(String? raw) {
  if (atlasFieldBlank(raw)) return const [];
  final data = jsonDecode(raw!);
  if (data is! List) return const [];
  return [
    for (final item in data)
      if (item is Map)
        AtlasSense(
          pos: '${item['pos'] ?? ''}',
          zh: '${item['zh'] ?? ''}',
          en: '${item['en'] ?? ''}',
        ),
  ];
}

List<AtlasExample> decodeExamples(String? raw) {
  if (atlasFieldBlank(raw)) return const [];
  final data = jsonDecode(raw!);
  if (data is! List) return const [];
  return [
    for (final item in data)
      if (item is Map)
        AtlasExample(en: '${item['en'] ?? ''}', zh: '${item['zh'] ?? ''}'),
  ];
}

List<String> decodeStringList(String? raw) {
  if (atlasFieldBlank(raw)) return const [];
  final data = jsonDecode(raw!);
  if (data is! List) return const [];
  return [for (final item in data) '$item'];
}

/// Minutes label is always an estimate: reviews are shorter than a first look.
int estimateStudyMinutes({required int reviews, required int newWords}) {
  final seconds = reviews * 12 + newWords * 28;
  if (seconds <= 0) return 0;
  return (seconds / 60).ceil();
}

part of 'app_database.dart';

class AtlasImportResult {
  const AtlasImportResult({
    required this.inserted,
    required this.reused,
    required this.bookId,
  });
  final int inserted;
  final int reused;
  final int bookId;
}

class AtlasQueueWord {
  const AtlasQueueWord({
    required this.id,
    required this.headword,
    required this.meaning,
    required this.pos,
    required this.cefr,
    required this.example,
    required this.atlasId,
    required this.mediaFlags,
    required this.stability,
    required this.isNew,
  });
  final int id;
  final String headword;
  final String meaning;
  final String pos;
  final String cefr;
  final String example;
  final String atlasId;
  final int mediaFlags;
  final double stability;
  final bool isNew;
}

class TodayJourney {
  const TodayJourney({
    required this.reviews,
    required this.newWords,
    required this.estimatedMinutes,
    required this.interrupted,
    required this.headword,
    required this.meaning,
    required this.atlasId,
  });
  final int reviews;
  final int newWords;
  final int estimatedMinutes;
  final bool interrupted;
  final String headword;
  final String meaning;
  final String atlasId;
}

class AtlasStats {
  const AtlasStats({
    required this.mastered,
    required this.firstCorrect,
    required this.firstAttempts,
  });
  final int mastered;
  final int firstCorrect;
  final int firstAttempts;
  int get firstAccuracy =>
      firstAttempts <= 0 ? 0 : (firstCorrect * 100 / firstAttempts).round();
}

class TopicProgress {
  const TopicProgress({
    required this.code,
    required this.label,
    required this.total,
    required this.started,
    required this.mastered,
  });
  final String code;
  final String label;
  final int total;
  final int started;
  final int mastered;
  double get mastery => total <= 0 ? 0 : mastered / total;
}

extension AtlasDatabase on AppDatabase {
  Future<int> ensureAtlasBook() async {
    final existing = await customSelect(
      'SELECT id, stable_id FROM word_books WHERE stable_id = ? OR source_file_name = ? ORDER BY id LIMIT 1',
      variables: [
        Variable<String>(atlasBookStableId),
        Variable<String>(atlasBookSource),
      ],
    ).getSingleOrNull();
    final now = DateTime.now().toUtc();
    if (existing != null) {
      final id = existing.read<int>('id');
      await customStatement(
        'UPDATE word_books SET stable_id = ?, name = ?, description = ?, language = ?, updated_at = ? WHERE id = ?',
        [
          atlasBookStableId,
          atlasBookTitle,
          '$atlasAttribution。$atlasDisclaimer',
          'en',
          now.millisecondsSinceEpoch ~/ 1000,
          id,
        ],
      );
      return id;
    }
    return into(wordBooks).insert(
      WordBooksCompanion.insert(
        name: atlasBookTitle,
        description: Value('$atlasAttribution。$atlasDisclaimer'),
        sourceFileName: const Value(atlasBookSource),
        language: const Value('en'),
        stableId: const Value(atlasBookStableId),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<AtlasImportResult> importAtlasEntries(List<AtlasEntryDraft> entries) {
    return transaction(() async {
      final bookId = await ensureAtlasBook();
      var inserted = 0;
      var reused = 0;
      for (final entry in entries) {
        if (entry.primaryZh.isEmpty) continue;
        final key = normalizeLookup(entry.word);
        final existing =
            await (select(words)..where(
                  (word) =>
                      word.language.equals('en') &
                      word.normalizedHeadword.equals(key) &
                      word.normalizedBaseForm.equals(''),
                ))
                .getSingleOrNull();
        final int wordId;
        if (existing == null) {
          wordId = await into(words).insert(
            WordDraft(
              korean: entry.word,
              meaningZh: entry.primaryZh,
              ipa: entry.ipaUs.isEmpty ? entry.ipaUk : entry.ipaUs,
              partOfSpeech: entry.primaryPos,
              exampleKo: entry.examples.isEmpty
                  ? null
                  : entry.examples.first.en,
              exampleZh: entry.examples.isEmpty
                  ? null
                  : entry.examples.first.zh,
              tags: topicLabel(entry.topic),
              note: entry.usageNote.isEmpty ? null : entry.usageNote,
            ).toCompanion(source: atlasBookSource, language: 'en'),
          );
          inserted += 1;
        } else {
          wordId = existing.id;
          reused += 1;
          await (update(words)..where((word) => word.id.equals(wordId))).write(
            WordsCompanion(
              meaningZh: isMissingMeaning(existing.meaningZh)
                  ? Value(entry.primaryZh)
                  : const Value.absent(),
              ipa: existing.ipa == null || existing.ipa!.trim().isEmpty
                  ? Value(
                      _nullable(
                        entry.ipaUs.isEmpty ? entry.ipaUk : entry.ipaUs,
                      ),
                    )
                  : const Value.absent(),
              partOfSpeech:
                  existing.partOfSpeech == null ||
                      existing.partOfSpeech!.trim().isEmpty
                  ? Value(_nullable(entry.primaryPos))
                  : const Value.absent(),
              exampleKo:
                  existing.exampleKo == null ||
                      existing.exampleKo!.trim().isEmpty
                  ? Value(
                      _nullable(
                        entry.examples.isEmpty ? null : entry.examples.first.en,
                      ),
                    )
                  : const Value.absent(),
              exampleZh:
                  existing.exampleZh == null ||
                      existing.exampleZh!.trim().isEmpty
                  ? Value(
                      _nullable(
                        entry.examples.isEmpty ? null : entry.examples.first.zh,
                      ),
                    )
                  : const Value.absent(),
              tags: existing.tags == null || existing.tags!.trim().isEmpty
                  ? Value(_nullable(topicLabel(entry.topic)))
                  : const Value.absent(),
              note: existing.note == null || existing.note!.trim().isEmpty
                  ? Value(_nullable(entry.usageNote))
                  : const Value.absent(),
              updatedAt: Value(DateTime.now().toUtc()),
            ),
          );
        }
        await _mergeAtlasRow(wordId, entry);
        await customStatement(
          'INSERT INTO word_book_words (word_book_id, word_id, sort_order) VALUES (?, ?, ?) '
          'ON CONFLICT(word_book_id, word_id) DO UPDATE SET sort_order = excluded.sort_order',
          [bookId, wordId, wordId],
        );
      }
      return AtlasImportResult(
        inserted: inserted,
        reused: reused,
        bookId: bookId,
      );
    });
  }

  Future<void> _mergeAtlasRow(int wordId, AtlasEntryDraft entry) async {
    final current = await atlasForWord(wordId);
    String keep(String? currentValue, String incoming) =>
        fillBlank(currentValue, incoming);
    String keepJson(String? currentValue, String incoming) =>
        atlasFieldBlank(currentValue) ? incoming : currentValue!;
    final senses = encodeAtlasList([
      for (final sense in entry.senses) sense.toJson(),
    ]);
    final examples = encodeAtlasList([
      for (final example in entry.examples) example.toJson(),
    ]);
    final values = [
      wordId,
      keep(current?.atlasId, entry.id),
      _nullable(keep(current?.ipaUk, entry.ipaUk)),
      _nullable(keep(current?.ipaUs, entry.ipaUs)),
      keepJson(
        current == null
            ? null
            : encodeAtlasList([
                for (final sense in current.senses) sense.toJson(),
              ]),
        senses,
      ),
      keepJson(
        current == null
            ? null
            : encodeAtlasList([
                for (final example in current.examples) example.toJson(),
              ]),
        examples,
      ),
      keepJson(
        current == null ? null : jsonEncode(current.collocations),
        jsonEncode(entry.collocations),
      ),
      keepJson(
        current == null ? null : jsonEncode(current.family),
        jsonEncode(entry.family),
      ),
      keepJson(
        current == null ? null : jsonEncode(current.synonyms),
        jsonEncode(entry.synonyms),
      ),
      keepJson(
        current == null ? null : jsonEncode(current.antonyms),
        jsonEncode(entry.antonyms),
      ),
      _nullable(keep(current?.tip, entry.tip)),
      _nullable(keep(current?.cefr, entry.cefr)),
      _nullable(keep(current?.topic, entry.topic)),
      current == null || current.mediaFlags == 0
          ? entry.mediaFlags
          : current.mediaFlags,
      _nullable(keep(current?.usageNote, entry.usageNote)),
    ];
    await customStatement(
      'INSERT INTO atlas_entries (word_id, atlas_id, ipa_uk, ipa_us, senses_json, examples_json, collocations_json, family_json, synonyms_json, antonyms_json, tip, cefr, topic, media_flags, usage_note) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(word_id) DO UPDATE SET '
      'atlas_id = excluded.atlas_id, ipa_uk = excluded.ipa_uk, ipa_us = excluded.ipa_us, '
      'senses_json = excluded.senses_json, examples_json = excluded.examples_json, '
      'collocations_json = excluded.collocations_json, family_json = excluded.family_json, '
      'synonyms_json = excluded.synonyms_json, antonyms_json = excluded.antonyms_json, '
      'tip = excluded.tip, cefr = excluded.cefr, topic = excluded.topic, '
      'media_flags = excluded.media_flags, usage_note = excluded.usage_note',
      values,
    );
  }

  Future<void> applyAtlasFill({
    required int wordId,
    required AtlasEntryDraft draft,
    required Set<String> fields,
  }) async {
    if (fields.isEmpty) return;
    final word = await (select(
      words,
    )..where((row) => row.id.equals(wordId))).getSingleOrNull();
    if (word == null) return;
    final current = await atlasForWord(wordId);
    final base = current == null
        ? AtlasEntryDraft(
            id: draft.id.isEmpty ? 'local-$wordId' : draft.id,
            word: word.headword,
            ipaUk: '',
            ipaUs: word.ipa ?? '',
            senses: const [],
            examples: const [],
            collocations: const [],
            family: const [],
            synonyms: const [],
            antonyms: const [],
            tip: '',
            cefr: '',
            topic: '',
            mediaFlags: 0,
            usageNote: '',
          )
        : AtlasEntryDraft(
            id: current.atlasId,
            word: word.headword,
            ipaUk: current.ipaUk,
            ipaUs: current.ipaUs,
            senses: current.senses,
            examples: current.examples,
            collocations: current.collocations,
            family: current.family,
            synonyms: current.synonyms,
            antonyms: current.antonyms,
            tip: current.tip,
            cefr: current.cefr,
            topic: current.topic,
            mediaFlags: current.mediaFlags,
            usageNote: current.usageNote,
          );
    final merged = AtlasEntryDraft(
      id: base.id,
      word: word.headword,
      ipaUk: fields.contains('ipaUk')
          ? fillBlank(base.ipaUk, draft.ipaUk)
          : base.ipaUk,
      ipaUs: fields.contains('ipaUs')
          ? fillBlank(base.ipaUs, draft.ipaUs)
          : base.ipaUs,
      senses: fields.contains('senses') && base.senses.isEmpty
          ? draft.senses
          : base.senses,
      examples: fields.contains('examples') && base.examples.isEmpty
          ? draft.examples
          : base.examples,
      collocations: fields.contains('collocations') && base.collocations.isEmpty
          ? draft.collocations
          : base.collocations,
      family: fields.contains('family') && base.family.isEmpty
          ? draft.family
          : base.family,
      synonyms: fields.contains('synonyms') && base.synonyms.isEmpty
          ? draft.synonyms
          : base.synonyms,
      antonyms: fields.contains('antonyms') && base.antonyms.isEmpty
          ? draft.antonyms
          : base.antonyms,
      tip: fields.contains('tip') ? fillBlank(base.tip, draft.tip) : base.tip,
      cefr: fields.contains('cefr')
          ? fillBlank(base.cefr, draft.cefr)
          : base.cefr,
      topic: fields.contains('topic')
          ? fillBlank(base.topic, draft.topic)
          : base.topic,
      mediaFlags: base.mediaFlags,
      usageNote: fields.contains('usageNote')
          ? fillBlank(base.usageNote, draft.usageNote)
          : base.usageNote,
    );
    await _mergeAtlasRow(wordId, merged);
    if (fields.contains('examples') &&
        (word.exampleKo == null || word.exampleKo!.trim().isEmpty) &&
        merged.examples.isNotEmpty) {
      await (update(words)..where((row) => row.id.equals(wordId))).write(
        WordsCompanion(
          exampleKo: Value(merged.examples.first.en),
          exampleZh: word.exampleZh == null || word.exampleZh!.trim().isEmpty
              ? Value(_nullable(merged.examples.first.zh))
              : const Value.absent(),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
    }
  }

  Future<AtlasRecord?> atlasForWord(int wordId) async {
    final row = await customSelect(
      'SELECT * FROM atlas_entries WHERE word_id = ?',
      variables: [Variable<int>(wordId)],
      readsFrom: {atlasEntries},
    ).getSingleOrNull();
    if (row == null) return null;
    return _atlasFromRow(row.data);
  }

  AtlasRecord _atlasFromRow(Map<String, Object?> data) => AtlasRecord(
    wordId: data['word_id'] as int,
    atlasId: '${data['atlas_id'] ?? ''}',
    ipaUk: '${data['ipa_uk'] ?? ''}',
    ipaUs: '${data['ipa_us'] ?? ''}',
    senses: decodeSenses(data['senses_json'] as String?),
    examples: decodeExamples(data['examples_json'] as String?),
    collocations: decodeStringList(data['collocations_json'] as String?),
    family: decodeStringList(data['family_json'] as String?),
    synonyms: decodeStringList(data['synonyms_json'] as String?),
    antonyms: decodeStringList(data['antonyms_json'] as String?),
    tip: '${data['tip'] ?? ''}',
    cefr: '${data['cefr'] ?? ''}',
    topic: '${data['topic'] ?? ''}',
    mediaFlags: data['media_flags'] as int? ?? 0,
    usageNote: '${data['usage_note'] ?? ''}',
  );

  Future<int> countMastered([String language = 'en']) async {
    final row = await customSelect(
      'SELECT COUNT(*) AS amount FROM study_cards WHERE language = ? AND state = 2 AND stability >= ?',
      variables: [
        Variable<String>(normalizeLearningLanguage(language)),
        Variable<double>(masteredStabilityDays.toDouble()),
      ],
      readsFrom: {studyCards},
    ).getSingle();
    return row.read<int>('amount');
  }

  Future<AtlasStats> loadAtlasStats([String language = 'en']) async {
    final lang = normalizeLearningLanguage(language);
    final mastered = await countMastered(lang);
    final row = await customSelect(
      'SELECT COALESCE(SUM(first_correct_count), 0) AS correct, COALESCE(SUM(first_attempt_count), 0) AS attempts FROM daily_statistics WHERE language = ?',
      variables: [Variable<String>(lang)],
      readsFrom: {dailyStatistics},
    ).getSingle();
    return AtlasStats(
      mastered: mastered,
      firstCorrect: row.read<int>('correct'),
      firstAttempts: row.read<int>('attempts'),
    );
  }

  Future<List<TopicProgress>> loadTopicProgress() async {
    final rows = await customSelect(
      'SELECT e.topic AS topic, COUNT(*) AS total, '
      'SUM(CASE WHEN s.id IS NOT NULL THEN 1 ELSE 0 END) AS started, '
      'SUM(CASE WHEN s.state = 2 AND s.stability >= ? THEN 1 ELSE 0 END) AS mastered '
      'FROM atlas_entries e JOIN words w ON w.id = e.word_id '
      'LEFT JOIN study_cards s ON s.word_id = w.id '
      "WHERE w.language = 'en' GROUP BY e.topic",
      variables: [Variable<double>(masteredStabilityDays.toDouble())],
      readsFrom: {atlasEntries, words, studyCards},
    ).get();
    final byCode = {for (final row in rows) '${row.data['topic']}': row};
    return [
      for (final topic in atlasTopics)
        TopicProgress(
          code: topic.$1,
          label: topic.$2,
          total: byCode[topic.$1]?.read<int>('total') ?? 0,
          started: byCode[topic.$1]?.read<int>('started') ?? 0,
          mastered: byCode[topic.$1]?.read<int>('mastered') ?? 0,
        ),
    ];
  }

  Future<TodayJourney> loadTodayJourney(DateTime now, String language) async {
    final lang = normalizeLearningLanguage(language);
    final plan = await loadDailyPlanProgress(now, lang);
    final round = await loadStudyRoundProgress(now, lang);
    final counts = await loadHomeCounts(now.toUtc(), lang);
    final reviewSlots = (plan.settings.reviewsPerDay - plan.reviewsDone)
        .clamp(0, plan.settings.reviewsPerDay)
        .toInt();
    final reviews = min(
      counts.due + counts.learningDue,
      reviewSlots + counts.learningDue,
    );
    final newSlots = round.remaining;
    final fresh = min(counts.newWords, newSlots);
    final session = await loadSetting(
      scopedSetting(lang, 'selected_learning_session'),
    );
    final interrupted =
        session != null && plan.totalDone > 0 && fresh + reviews > 0;
    final word = await _wordOfDay(now, lang);
    return TodayJourney(
      reviews: reviews,
      newWords: fresh,
      estimatedMinutes: estimateStudyMinutes(reviews: reviews, newWords: fresh),
      interrupted: interrupted,
      headword: word?.$1 ?? '',
      meaning: word?.$2 ?? '',
      atlasId: word?.$3 ?? '',
    );
  }

  Future<(String, String, String?)?> _wordOfDay(
    DateTime now,
    String language,
  ) async {
    final total = await customSelect(
      'SELECT COUNT(*) AS amount FROM words WHERE language = ?',
      variables: [Variable<String>(language)],
    ).getSingle();
    final amount = total.read<int>('amount');
    if (amount == 0) return null;
    final index = (dayKey(now).hashCode & 0x7fffffff) % amount;
    final row = await customSelect(
      'SELECT w.id, w.headword, w.meaning_zh, e.atlas_id, e.media_flags '
      'FROM words w LEFT JOIN atlas_entries e ON e.word_id = w.id '
      'WHERE w.language = ? ORDER BY w.id LIMIT 1 OFFSET ?',
      variables: [Variable<String>(language), Variable<int>(index)],
      readsFrom: {words, atlasEntries},
    ).getSingleOrNull();
    if (row == null) return null;
    final flags = row.data['media_flags'] as int? ?? 0;
    final atlasId = '${row.data['atlas_id'] ?? ''}';
    final thumb =
        language == 'en' && atlasId.isNotEmpty && (flags & atlasMediaImage) != 0
        ? atlasId
        : '';
    return (
      row.read<String>('headword'),
      row.read<String>('meaning_zh'),
      thumb,
    );
  }

  Future<List<AtlasQueueWord>> loadAtlasQueue(
    SessionOptions options,
    DateTime now, {
    required bool reviewsOnly,
  }) async {
    final lang = normalizeLearningLanguage(options.language);
    final plan = await loadDailyPlanProgress(now, lang);
    final round = await loadStudyRoundProgress(now, lang);
    final due = now.toUtc();
    final reviewCap = reviewsOnly
        ? 500
        : (plan.settings.reviewsPerDay - plan.reviewsDone).clamp(0, 500);
    final newCap = reviewsOnly ? 0 : round.remaining;
    final bookClause = options.bookId == null
        ? ''
        : 'AND EXISTS (SELECT 1 FROM word_book_words b WHERE b.word_id = w.id AND b.word_book_id = ?)';
    final bookVar = options.bookId == null
        ? const <Variable>[]
        : [Variable<int>(options.bookId!)];
    Future<List<AtlasQueueWord>> query(
      String where,
      List<Variable> vars,
      int limit,
    ) async {
      if (limit <= 0) return const [];
      final rows = await customSelect(
        'SELECT w.id, w.headword, w.meaning_zh, w.part_of_speech, w.example_ko, '
        'e.atlas_id, e.cefr, e.media_flags, COALESCE(s.stability, 0) AS stability, '
        'CASE WHEN s.id IS NULL THEN 1 ELSE 0 END AS is_new '
        'FROM words w LEFT JOIN study_cards s ON s.word_id = w.id '
        'LEFT JOIN atlas_entries e ON e.word_id = w.id '
        'WHERE w.language = ? AND $where $bookClause '
        "AND NOT EXISTS (SELECT 1 FROM app_settings a WHERE a.key = 'word_status:' || w.id AND a.value IN ('suspended', 'known')) "
        'ORDER BY COALESCE(s.due, w.id), w.id LIMIT ?',
        variables: [
          Variable<String>(lang),
          ...vars,
          ...bookVar,
          Variable<int>(limit),
        ],
        readsFrom: {
          words,
          studyCards,
          atlasEntries,
          appSettings,
          wordBookWords,
        },
      ).get();
      return [for (final row in rows) _queueWord(row)];
    }

    final learning = await query('s.state IN (1, 3) AND s.due <= ?', [
      Variable<DateTime>(due),
    ], 500);
    final reviews = await query('s.state = 2 AND s.due <= ?', [
      Variable<DateTime>(due),
    ], reviewCap.toInt());
    final fresh = await query('s.id IS NULL', const [], newCap);
    return [...learning, ...reviews, ...fresh];
  }

  AtlasQueueWord _queueWord(QueryRow row) => AtlasQueueWord(
    id: row.read<int>('id'),
    headword: row.read<String>('headword'),
    meaning: row.read<String>('meaning_zh'),
    pos: '${row.data['part_of_speech'] ?? ''}',
    cefr: '${row.data['cefr'] ?? ''}',
    example: '${row.data['example_ko'] ?? ''}',
    atlasId: '${row.data['atlas_id'] ?? ''}',
    mediaFlags: row.data['media_flags'] as int? ?? 0,
    stability: (row.data['stability'] as num?)?.toDouble() ?? 0,
    isNew: row.read<int>('is_new') == 1,
  );

  Future<List<AtlasQueueWord>> typingSources({
    required String language,
    required String source,
    int? bookId,
    int limit = 40,
  }) async {
    final lang = normalizeLearningLanguage(language);
    final where = <String>['w.language = ?'];
    final variables = <Variable>[Variable<String>(lang)];
    if (source == 'wrong') where.add('u.is_difficult = 1');
    if (source == 'favorite') where.add('u.is_favorite = 1');
    if (source == 'recent') where.add('u.last_seen_at IS NOT NULL');
    if (bookId != null) {
      where.add(
        'EXISTS (SELECT 1 FROM word_book_words b WHERE b.word_id = w.id AND b.word_book_id = ?)',
      );
      variables.add(Variable<int>(bookId));
    }
    final order = source == 'recent'
        ? 'u.last_seen_at DESC'
        : 'w.headword, w.id';
    final rows = await customSelect(
      'SELECT w.id, w.headword, w.meaning_zh, w.part_of_speech, w.example_ko, '
      'e.atlas_id, e.cefr, e.media_flags, 0 AS stability, 0 AS is_new '
      'FROM words w LEFT JOIN user_words u ON u.word_id = w.id '
      'LEFT JOIN atlas_entries e ON e.word_id = w.id '
      'WHERE ${where.join(' AND ')} ORDER BY $order LIMIT ?',
      variables: [...variables, Variable<int>(limit)],
      readsFrom: {words, userWords, atlasEntries, wordBookWords},
    ).get();
    return [for (final row in rows) _queueWord(row)];
  }
}

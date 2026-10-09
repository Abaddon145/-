// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

class Words extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get korean => text()();
  TextColumn get normalizedKorean => text()();
  TextColumn get baseForm => text().withDefault(const Constant(''))();
  TextColumn get normalizedBaseForm => text().withDefault(const Constant(''))();
  TextColumn get meaningZh => text()();
  TextColumn get pronunciation => text().nullable()();
  TextColumn get partOfSpeech => text().nullable()();
  TextColumn get exampleKo => text().nullable()();
  TextColumn get exampleZh => text().nullable()();
  TextColumn get topikLevel => text().nullable()();
  TextColumn get category => text().nullable()();
  TextColumn get tags => text().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get hanja => text().nullable()();
  TextColumn get etymology => text().nullable()();
  TextColumn get source => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {normalizedKorean, normalizedBaseForm},
      ];
}

class WordBooks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get sourceFileName => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

class WordBookWords extends Table {
  IntColumn get wordBookId => integer().references(WordBooks, #id)();
  IntColumn get wordId => integer().references(Words, #id)();
  IntColumn get sortOrder => integer()();

  @override
  Set<Column<Object>> get primaryKey => {wordBookId, wordId};
}

class StudyCards extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get wordId => integer().unique().references(Words, #id)();
  IntColumn get state => integer().withDefault(const Constant(0))();
  DateTimeColumn get due => dateTime()();
  RealColumn get stability => real().withDefault(const Constant(0))();
  RealColumn get difficulty => real().withDefault(const Constant(0))();
  IntColumn get elapsedDays => integer().withDefault(const Constant(0))();
  IntColumn get scheduledDays => integer().withDefault(const Constant(0))();
  IntColumn get reps => integer().withDefault(const Constant(0))();
  IntColumn get lapses => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastReview => dateTime().nullable()();
  TextColumn get fsrsJson => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

class ReviewLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get wordId => integer().references(Words, #id)();
  TextColumn get submissionToken => text().unique()();
  IntColumn get rating => integer()();
  DateTimeColumn get reviewedAt => dateTime()();
  IntColumn get stateBefore => integer()();
  IntColumn get stateAfter => integer()();
  IntColumn get elapsedDays => integer()();
  IntColumn get scheduledDays => integer()();
  IntColumn get durationMs => integer()();
  TextColumn get fsrsReviewLogJson => text()();
}

class UserWords extends Table {
  IntColumn get wordId => integer().references(Words, #id)();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  BoolColumn get isDifficult => boolean().withDefault(const Constant(false))();
  TextColumn get note => text().nullable()();
  IntColumn get correctCount => integer().withDefault(const Constant(0))();
  IntColumn get wrongCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastSeenAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {wordId};
}

class DailyStatistics extends Table {
  DateTimeColumn get date => dateTime()();
  IntColumn get newWords => integer().withDefault(const Constant(0))();
  IntColumn get reviewWords => integer().withDefault(const Constant(0))();
  IntColumn get correctCount => integer().withDefault(const Constant(0))();
  IntColumn get wrongCount => integer().withDefault(const Constant(0))();
  IntColumn get studyDurationMs => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {date};
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DriftDatabase(
  tables: [
    Words,
    WordBooks,
    WordBookWords,
    StudyCards,
    ReviewLogs,
    UserWords,
    DailyStatistics,
    AppSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(
          executor ??
              driftDatabase(
                name: 'korean_memo',
                web: DriftWebOptions(
                  sqlite3Wasm: Uri.parse('sqlite3.wasm'),
                  driftWorker: Uri.parse('drift_worker.js'),
                ),
              ),
        );

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (migrator) => migrator.createAll(),
        onUpgrade: (migrator, from, to) async {
          if (from < 2) {
            await migrator.createTable(appSettings);
          }
        },
      );

  Future<HomeCounts> loadHomeCounts(DateTime nowUtc) async {
    final dueResult = await customSelect(
      'SELECT COUNT(*) AS amount FROM study_cards WHERE due <= ?',
      variables: [Variable<DateTime>(nowUtc)],
      readsFrom: {studyCards},
    ).getSingle();
    final newResult = await customSelect(
      'SELECT COUNT(*) AS amount FROM words w '
      'WHERE NOT EXISTS (SELECT 1 FROM study_cards s WHERE s.word_id = w.id)',
      readsFrom: {words, studyCards},
    ).getSingle();
    final learnedResult = await customSelect(
      'SELECT COUNT(*) AS amount FROM review_logs',
      readsFrom: {reviewLogs},
    ).getSingle();
    return HomeCounts(
      due: dueResult.read<int>('amount'),
      newWords: newResult.read<int>('amount'),
      completed: learnedResult.read<int>('amount'),
    );
  }

  Future<DailyPlanSettings> loadDailyPlanSettings() async {
    final rows = await (select(appSettings)
          ..where((row) => row.key.isIn(const [
                DailyPlanSettings.newWordsKey,
                DailyPlanSettings.reviewsKey,
              ])))
        .get();
    final values = {for (final row in rows) row.key: int.tryParse(row.value)};
    return DailyPlanSettings(
      newWordsPerDay:
          values[DailyPlanSettings.newWordsKey] ??
              DailyPlanSettings.defaultNewWords,
      reviewsPerDay:
          values[DailyPlanSettings.reviewsKey] ??
              DailyPlanSettings.defaultReviews,
    ).normalized();
  }

  Future<void> saveDailyPlanSettings(DailyPlanSettings settings) async {
    final normalized = settings.normalized();
    final now = DateTime.now().toUtc();
    await transaction(() async {
    await batch((batch) {
      batch.insertAllOnConflictUpdate(appSettings, [
        AppSettingsCompanion.insert(
          key: DailyPlanSettings.newWordsKey,
          value: normalized.newWordsPerDay.toString(),
          updatedAt: now,
        ),
        AppSettingsCompanion.insert(
          key: DailyPlanSettings.reviewsKey,
          value: normalized.reviewsPerDay.toString(),
          updatedAt: now,
        ),
      ]);
    });
      await (delete(appSettings)..where((row) => row.key.isIn(const [
        'study_round_day', 'study_round_baseline', 'study_round_target',
      ]))).go();
    });
  }

  Future<String?> loadSetting(String key) async {
    final row = await (select(appSettings)..where((item) => item.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> saveSetting(String key, String? value) async {
    if (value == null) {
      await (delete(appSettings)..where((item) => item.key.equals(key))).go();
      return;
    }
    await into(appSettings).insertOnConflictUpdate(
      AppSettingsCompanion.insert(
        key: key,
        value: value,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<DailyPlanProgress> loadDailyPlanProgress(DateTime localNow) async {
    final settings = await loadDailyPlanSettings();
    final day = _dailyStatKey(localNow);
    final statistics = await (select(dailyStatistics)
          ..where((row) => row.date.equals(day)))
        .getSingleOrNull();
    return DailyPlanProgress(
      settings: settings,
      newWordsDone: statistics?.newWords ?? 0,
      reviewsDone: statistics?.reviewWords ?? 0,
      correctCount: statistics?.correctCount ?? 0,
      wrongCount: statistics?.wrongCount ?? 0,
      studyDurationMs: statistics?.studyDurationMs ?? 0,
    );
  }

  Future<StudyRoundProgress> loadStudyRoundProgress(DateTime localNow) async {
    final progress = await loadDailyPlanProgress(localNow);
    final day = await loadSetting('study_round_day');
    final active = day == _dailyStatKey(localNow).toIso8601String();
    final baseline = active
        ? int.tryParse(await loadSetting('study_round_baseline') ?? '') ?? 0
        : 0;
    final target = active
        ? int.tryParse(await loadSetting('study_round_target') ?? '') ?? progress.settings.newWordsPerDay
        : progress.settings.newWordsPerDay;
    return StudyRoundProgress(
      totalNewWords: progress.newWordsDone,
      baseline: baseline < 0 ? 0 : baseline,
      target: target < 1 ? progress.settings.newWordsPerDay : target,
      isExtra: active,
    );
  }

  Future<void> startExtraStudyRound(DateTime localNow, int count) async {
    if (count < 1) {
      throw const FormatException('请输入大于 0 的整数');
    }
    await transaction(() async {
      final progress = await loadDailyPlanProgress(localNow);
      await saveSetting('study_round_day', _dailyStatKey(localNow).toIso8601String());
      await saveSetting('study_round_baseline', progress.newWordsDone.toString());
      await saveSetting('study_round_target', count.toString());
    });
  }

  Future<Word?> nextStudyWord(
    DateTime nowUtc, {
    required DateTime localNow,
    int? bookId,
  }) async {
    final progress = await loadDailyPlanProgress(localNow);

    if (progress.reviewsDone < progress.settings.reviewsPerDay) {
      final dueQuery = select(words).join([
        innerJoin(studyCards, studyCards.wordId.equalsExp(words.id)),
        if (bookId != null)
          innerJoin(wordBookWords, wordBookWords.wordId.equalsExp(words.id) & wordBookWords.wordBookId.equals(bookId)),
      ])
        ..where(studyCards.due.isSmallerOrEqualValue(nowUtc) &
            (bookId != null ? const Constant<bool>(true) : words.category.isNull() | words.category.equals('工业术语·待补中文').not()))
        ..orderBy([OrderingTerm.asc(studyCards.due)])
        ..limit(1);
      final dueRow = await dueQuery.getSingleOrNull();
      if (dueRow != null) return dueRow.readTable(words);
    }

    final round = await loadStudyRoundProgress(localNow);
    if (progress.newWordsDone >= round.baseline + round.target) return null;

    final newQuery = select(words).join([
      leftOuterJoin(studyCards, studyCards.wordId.equalsExp(words.id)),
      if (bookId != null)
        innerJoin(wordBookWords, wordBookWords.wordId.equalsExp(words.id) & wordBookWords.wordBookId.equals(bookId)),
    ])
      ..where(studyCards.id.isNull() &
          (bookId != null ? const Constant<bool>(true) : words.category.isNull() | words.category.equals('工业术语·待补中文').not()))
      ..orderBy([OrderingTerm.asc(words.id)])
      ..limit(1);
    final newRow = await newQuery.getSingleOrNull();
    return newRow?.readTable(words);
  }

  Future<List<WordBook>> loadWordBooks() => (select(wordBooks)
    ..orderBy([(row) => OrderingTerm.asc(row.id)])).get();

  Future<HomeCounts> loadScopedStudyCounts(int? bookId) async {
    final scope = bookId == null
        ? "COALESCE(w.category, '') != '工业术语·待补中文'"
        : 'EXISTS (SELECT 1 FROM word_book_words b WHERE b.word_id=w.id AND b.word_book_id=?)';
    final variables = bookId == null ? <Variable>[] : <Variable>[Variable<int>(bookId)];
    final fresh = await customSelect(
      'SELECT COUNT(*) AS amount FROM words w WHERE $scope AND NOT EXISTS '
      '(SELECT 1 FROM study_cards s WHERE s.word_id=w.id)',
      variables: variables, readsFrom: {words, wordBookWords, studyCards},
    ).getSingle();
    return HomeCounts(due: 0, newWords: fresh.read<int>('amount'), completed: 0);
  }

  Future<StudyCard?> cardForWord(int wordId) {
    return (select(studyCards)..where((row) => row.wordId.equals(wordId)))
        .getSingleOrNull();
  }

  Future<int> createWordBook({
    required String name,
    required String sourceFileName,
  }) {
    final now = DateTime.now().toUtc();
    return into(wordBooks).insert(
      WordBooksCompanion.insert(
        name: name,
        sourceFileName: Value(sourceFileName),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<ImportWriteResult> importWords({
    required int wordBookId,
    required List<WordDraft> drafts,
    required String source,
  }) {
    return transaction(
      () => _writeWords(
        wordBookId: wordBookId,
        drafts: drafts,
        source: source,
      ),
    );
  }

  Future<ImportWriteResult?> importWordBookIfMissing({
    required String name,
    required String sourceFileName,
    required List<WordDraft> drafts,
  }) {
    return transaction(() async {
      final existingBook = await (select(wordBooks)
            ..where((row) => row.sourceFileName.equals(sourceFileName)))
          .getSingleOrNull();
      if (existingBook != null) return null;

      final now = DateTime.now().toUtc();
      final wordBookId = await into(wordBooks).insert(
        WordBooksCompanion.insert(
          name: name,
          sourceFileName: Value(sourceFileName),
          createdAt: now,
          updatedAt: now,
        ),
      );
      return _writeWords(
        wordBookId: wordBookId,
        drafts: drafts,
        source: sourceFileName,
      );
    });
  }

  Future<int> addManualWord(WordDraft draft) => transaction(() async {
    if (draft.korean.trim().isEmpty ||
        draft.meaningZh.trim().isEmpty ||
        (draft.partOfSpeech?.trim().isEmpty ?? true)) {
      throw const FormatException('请填写韩语、中文释义和词性');
    }
    final existing = await (select(words)
          ..where((word) =>
              word.normalizedKorean.equals(draft.normalizedKorean) &
              word.normalizedBaseForm.equals(draft.normalizedBaseForm)))
        .getSingleOrNull();
    if (existing != null) {
      throw const FormatException('这个单词已存在，请在词库中编辑');
    }
    const source = 'manual://words';
    final book = await (select(wordBooks)
          ..where((item) => item.sourceFileName.equals(source)))
        .getSingleOrNull();
    final now = DateTime.now().toUtc();
    final bookId = book?.id ??
        await into(wordBooks).insert(
          WordBooksCompanion.insert(
            name: '手动录入',
            sourceFileName: const Value(source),
            createdAt: now,
            updatedAt: now,
          ),
        );
    final wordId = await into(words).insert(
      draft.toCompanion(source: '手动录入'),
    );
    await into(wordBookWords).insert(
      WordBookWordsCompanion.insert(
        wordBookId: bookId,
        wordId: wordId,
        sortOrder: wordId,
      ),
    );
    return wordId;
  });

  Future<ImportWriteResult> _writeWords({
    required int wordBookId,
    required List<WordDraft> drafts,
    required String source,
  }) async {
    var inserted = 0;
    var reused = 0;
    for (var index = 0; index < drafts.length; index++) {
      final draft = drafts[index];
      final existing = await (select(words)
            ..where((row) =>
                row.normalizedKorean.equals(draft.normalizedKorean) &
                row.normalizedBaseForm.equals(draft.normalizedBaseForm)))
          .getSingleOrNull();
      final wordId = existing?.id ??
          await into(words).insert(
            draft.toCompanion(source: source),
          );
      if (existing == null) {
        inserted++;
      } else {
        reused++;
      }
      await into(wordBookWords).insertOnConflictUpdate(
        WordBookWordsCompanion.insert(
          wordBookId: wordBookId,
          wordId: wordId,
          sortOrder: index,
        ),
      );
    }
    return ImportWriteResult(inserted: inserted, reused: reused);
  }

  Future<void> persistReview({
    required int wordId,
    required String submissionToken,
    required int rating,
    required DateTime reviewedAt,
    required int durationMs,
    required DateTime localDay,
    required Map<String, Object?> cardMap,
    required Map<String, Object?> reviewLogMap,
  }) {
    return transaction(() async {
      final previous = await cardForWord(wordId);
      final now = reviewedAt.toUtc();
      final due = _dateTime(cardMap['due']) ?? now;
      final companion = StudyCardsCompanion(
        wordId: Value(wordId),
        state: Value(_integer(cardMap['state'])),
        due: Value(due),
        stability: Value(_double(cardMap['stability'])),
        difficulty: Value(_double(cardMap['difficulty'])),
        elapsedDays: Value(_integer(cardMap['elapsed_days'])),
        scheduledDays: Value(_integer(cardMap['scheduled_days'])),
        reps: Value(_integer(cardMap['reps'])),
        lapses: Value(_integer(cardMap['lapses'])),
        lastReview: Value(_dateTime(cardMap['last_review'])),
        fsrsJson: Value(jsonEncode(cardMap)),
        createdAt: Value(previous?.createdAt ?? now),
        updatedAt: Value(now),
      );
      if (previous == null) {
        await into(studyCards).insert(companion);
      } else {
        await (update(studyCards)..where((row) => row.wordId.equals(wordId)))
            .write(companion);
      }
      await into(reviewLogs).insert(
        ReviewLogsCompanion.insert(
          wordId: wordId,
          submissionToken: submissionToken,
          rating: rating,
          reviewedAt: now,
          stateBefore: previous?.state ?? 0,
          stateAfter: _integer(cardMap['state']),
          elapsedDays: _integer(reviewLogMap['elapsed_days']),
          scheduledDays: _integer(reviewLogMap['scheduled_days']),
          durationMs: durationMs,
          fsrsReviewLogJson: jsonEncode(reviewLogMap),
        ),
      );

      final day = _dailyStatKey(localDay);
      final statistics = await (select(dailyStatistics)
            ..where((row) => row.date.equals(day)))
          .getSingleOrNull();
      final isNewWord = previous == null;
      final isWrong = rating == 1;
      if (statistics == null) {
        await into(dailyStatistics).insert(
          DailyStatisticsCompanion.insert(
            date: day,
            newWords: Value(isNewWord ? 1 : 0),
            reviewWords: Value(isNewWord ? 0 : 1),
            correctCount: Value(isWrong ? 0 : 1),
            wrongCount: Value(isWrong ? 1 : 0),
            studyDurationMs: Value(durationMs),
          ),
        );
      } else {
        await (update(dailyStatistics)..where((row) => row.date.equals(day)))
            .write(
          DailyStatisticsCompanion(
            newWords: Value(statistics.newWords + (isNewWord ? 1 : 0)),
            reviewWords: Value(statistics.reviewWords + (isNewWord ? 0 : 1)),
            correctCount:
                Value(statistics.correctCount + (isWrong ? 0 : 1)),
            wrongCount: Value(statistics.wrongCount + (isWrong ? 1 : 0)),
            studyDurationMs:
                Value(statistics.studyDurationMs + durationMs),
          ),
        );
      }
      await customStatement('INSERT INTO user_words (word_id,is_favorite,is_difficult,correct_count,wrong_count,last_seen_at) VALUES (?,0,?,?,?,?) '
        'ON CONFLICT(word_id) DO UPDATE SET is_difficult=CASE WHEN excluded.is_difficult=1 THEN 1 ELSE user_words.is_difficult END, '
        'correct_count=user_words.correct_count+excluded.correct_count, wrong_count=user_words.wrong_count+excluded.wrong_count, last_seen_at=excluded.last_seen_at',
        [wordId,isWrong?1:0,isWrong?0:1,isWrong?1:0,now.millisecondsSinceEpoch]);
    });
  }
  Future<List<LibraryWordEntry>> searchLibraryWords({
    required String query,
    required LibraryFilter filter,
    int? bookId,
  }) async {
    final normalized = normalizeLookup(query);
    final search = normalized.isEmpty
        ? const Constant<bool>(true)
        : words.korean.lower().like('%$normalized%') |
            words.meaningZh.lower().like('%$normalized%') |
            words.baseForm.lower().like('%$normalized%');
    final filterExpression = switch (filter) {
      LibraryFilter.all => const Constant<bool>(true),
      LibraryFilter.favorites => userWords.isFavorite.equals(true),
      LibraryFilter.wrong => userWords.wrongCount.isBiggerThanValue(0),
    };
    final queryBuilder = select(words).join([
      leftOuterJoin(userWords, userWords.wordId.equalsExp(words.id)),
      if (bookId != null)
        innerJoin(wordBookWords, wordBookWords.wordId.equalsExp(words.id) & wordBookWords.wordBookId.equals(bookId)),
    ])
      ..where(search & filterExpression)
      ..orderBy([OrderingTerm.asc(words.korean)])
      ..limit(5000);
    final rows = await queryBuilder.get();
    return rows.map((row) {
      final userWord = row.readTableOrNull(userWords);
      return LibraryWordEntry(
        word: row.readTable(words),
        isFavorite: userWord?.isFavorite ?? false,
        wrongCount: userWord?.wrongCount ?? 0,
      );
    }).toList();
  }

  Future<void> setFavorite(int id, bool value) => customStatement(
    'INSERT INTO user_words (word_id, is_favorite, is_difficult, correct_count, wrong_count) VALUES (?, ?, 0, 0, 0) '
    'ON CONFLICT(word_id) DO UPDATE SET is_favorite = excluded.is_favorite', [id, value ? 1 : 0]);

  Future<void> updateWord({
    required int wordId,
    required String korean,
    required String meaningZh,
    String? partOfSpeech,
  }) async {
    final term = korean.trim();
    final meaning = meaningZh.trim();
    if (term.isEmpty || meaning.isEmpty) {
      throw ArgumentError('韩语词条和中文释义不能为空');
    }
    await (update(words)..where((word) => word.id.equals(wordId))).write(
      WordsCompanion(
        korean: Value(term),
        normalizedKorean: Value(normalizeLookup(term)),
        meaningZh: Value(meaning),
        partOfSpeech: partOfSpeech == null
            ? const Value.absent()
            : Value(_nullable(partOfSpeech)),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> deleteWord(int id) => transaction(() async {
    await (delete(reviewLogs)..where((r) => r.wordId.equals(id))).go();
    await (delete(studyCards)..where((r) => r.wordId.equals(id))).go();
    await (delete(userWords)..where((r) => r.wordId.equals(id))).go();
    await (delete(wordBookWords)..where((r) => r.wordId.equals(id))).go();
    await (delete(words)..where((r) => r.id.equals(id))).go();
  });

  Future<List<DailyStatisticsSummary>> loadRecentStatistics(DateTime now) async {
    final today = DateTime.utc(now.year, now.month, now.day), start = DateTime.utc(now.year, now.month, now.day).subtract(const Duration(days: 6));
    final rows = await (select(dailyStatistics)..where((r) => r.date.isBiggerOrEqualValue(start) & r.date.isSmallerOrEqualValue(today))
      ..orderBy([(r) => OrderingTerm.asc(r.date)])).get();
    final values = {for (final r in rows) r.date: r};
    return List.generate(7, (i) { final d = start.add(Duration(days:i)), r = values[d];
      return DailyStatisticsSummary(date:d,newWords:r?.newWords??0,reviews:r?.reviewWords??0,
        correct:r?.correctCount??0,wrong:r?.wrongCount??0,durationMs:r?.studyDurationMs??0); });
  }

  Future<Map<String,Object?>> createBackupSnapshot() async {
    const tables=['words','word_books','word_book_words','study_cards','review_logs','user_words','daily_statistics','app_settings'];
    final data=<String,List<Map<String,Object?>>>{};
    for(final t in tables){ final rows=await customSelect('SELECT * FROM $t').get(); data[t]=rows.map((r)=>Map<String,Object?>.from(r.data)).toList(); }
    return {'format':'korean-memo-backup','version':1,'createdAt':DateTime.now().toUtc().toIso8601String(),'tables':data};
  }

  Future<void> restoreBackupSnapshot(Map<String,dynamic> snapshot) async {
    const columns=<String,List<String>>{
      'words':['id','korean','normalized_korean','base_form','normalized_base_form','meaning_zh','pronunciation','part_of_speech','example_ko','example_zh','topik_level','category','tags','note','hanja','etymology','source','created_at','updated_at'],
      'word_books':['id','name','description','source_file_name','created_at','updated_at'],
      'word_book_words':['word_book_id','word_id','sort_order'],
      'study_cards':['id','word_id','state','due','stability','difficulty','elapsed_days','scheduled_days','reps','lapses','last_review','fsrs_json','created_at','updated_at'],
      'review_logs':['id','word_id','submission_token','rating','reviewed_at','state_before','state_after','elapsed_days','scheduled_days','duration_ms','fsrs_review_log_json'],
      'user_words':['word_id','is_favorite','is_difficult','note','correct_count','wrong_count','last_seen_at'],
      'daily_statistics':['date','new_words','review_words','correct_count','wrong_count','study_duration_ms'],
      'app_settings':['key','value','updated_at'],
    };
    if(snapshot['format']!='korean-memo-backup'||snapshot['version']!=1) throw const FormatException('不支持的备份格式');
    final payload=snapshot['tables']; if(payload is! Map) throw const FormatException('备份缺少数据');
    for(final e in columns.entries){ final list=payload[e.key]; if(list is! List||list.length>100000) throw FormatException('备份表无效：${e.key}');
      for(final r in list){if(r is! Map||r.keys.toSet().length!=e.value.length||!e.value.every(r.containsKey)) throw FormatException('备份字段无效：${e.key}');}}
    await transaction(() async {
      for(final t in ['review_logs','study_cards','word_book_words','user_words','daily_statistics','app_settings','words','word_books']) await customStatement('DELETE FROM $t');
      for(final t in columns.keys){for(final raw in payload[t] as List){final row=Map<String,Object?>.from(raw as Map), names=columns[t]!;
        await customStatement('INSERT INTO $t (${names.join(',')}) VALUES (${List.filled(names.length,'?').join(',')})',[for(final n in names) row[n]]);}}
    });
  }

}

class DailyPlanSettings {
  const DailyPlanSettings({
    required this.newWordsPerDay,
    required this.reviewsPerDay,
  });

  static const newWordsKey = 'daily_new_words';
  static const reviewsKey = 'daily_reviews';
  static const defaultNewWords = 20;
  static const defaultReviews = 100;

  final int newWordsPerDay;
  final int reviewsPerDay;

  DailyPlanSettings normalized() => DailyPlanSettings(
        newWordsPerDay: newWordsPerDay < 1 ? 1 : newWordsPerDay,
        reviewsPerDay: reviewsPerDay.clamp(1, 500).toInt(),
      );
}

class StudyRoundProgress {
  const StudyRoundProgress({
    required this.totalNewWords,
    required this.baseline,
    required this.target,
    required this.isExtra,
  });
  final int totalNewWords;
  final int baseline;
  final int target;
  final bool isExtra;
  int get done => (totalNewWords - baseline).clamp(0, target).toInt();
  int get remaining => target - done;
}

class DailyPlanProgress {
  const DailyPlanProgress({
    required this.settings,
    required this.newWordsDone,
    required this.reviewsDone,
    required this.correctCount,
    required this.wrongCount,
    required this.studyDurationMs,
  });

  final DailyPlanSettings settings;
  final int newWordsDone;
  final int reviewsDone;
  final int correctCount;
  final int wrongCount;
  final int studyDurationMs;

  int get totalDone => newWordsDone + reviewsDone;
  int get totalLimit =>
      settings.newWordsPerDay + settings.reviewsPerDay;
  double get progress =>
      totalLimit == 0 ? 0 : (totalDone / totalLimit).clamp(0, 1).toDouble();
}

class HomeCounts {
  const HomeCounts({
    required this.due,
    required this.newWords,
    required this.completed,
  });

  final int due;
  final int newWords;
  final int completed;
}

class ImportWriteResult {
  const ImportWriteResult({required this.inserted, required this.reused});

  final int inserted;
  final int reused;
}

class WordDraft {
  const WordDraft({
    required this.korean,
    required this.meaningZh,
    this.baseForm = '',
    this.pronunciation,
    this.partOfSpeech,
    this.exampleKo,
    this.exampleZh,
    this.topikLevel,
    this.category,
    this.tags,
    this.note,
    this.hanja,
    this.etymology,
  });

  final String korean;
  final String meaningZh;
  final String baseForm;
  final String? pronunciation;
  final String? partOfSpeech;
  final String? exampleKo;
  final String? exampleZh;
  final String? topikLevel;
  final String? category;
  final String? tags;
  final String? note;
  final String? hanja;
  final String? etymology;

  String get normalizedKorean => normalizeLookup(korean);
  String get normalizedBaseForm => normalizeLookup(baseForm);

  WordsCompanion toCompanion({required String source}) {
    final now = DateTime.now().toUtc();
    return WordsCompanion.insert(
      korean: korean.trim(),
      normalizedKorean: normalizedKorean,
      baseForm: Value(baseForm.trim()),
      normalizedBaseForm: Value(normalizedBaseForm),
      meaningZh: meaningZh.trim(),
      pronunciation: Value(_nullable(pronunciation)),
      partOfSpeech: Value(_nullable(partOfSpeech)),
      exampleKo: Value(_nullable(exampleKo)),
      exampleZh: Value(_nullable(exampleZh)),
      topikLevel: Value(_nullable(topikLevel)),
      category: Value(_nullable(category)),
      tags: Value(_nullable(tags)),
      note: Value(_nullable(note)),
      hanja: Value(_nullable(hanja)),
      etymology: Value(_nullable(etymology)),
      source: Value(source),
      createdAt: now,
      updatedAt: now,
    );
  }
}

String normalizeLookup(String value) {
  return value.replaceAll(RegExp(r'[\s\u3000]+'), ' ').trim().toLowerCase();
}

String? _nullable(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

int _integer(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _double(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime? _dateTime(Object? value) {
  if (value is DateTime) return value.toUtc();
  return DateTime.tryParse(value?.toString() ?? '')?.toUtc();
}

DateTime _dailyStatKey(DateTime localDate) =>
    DateTime.utc(localDate.year, localDate.month, localDate.day);

enum LibraryFilter { all, favorites, wrong }
class LibraryWordEntry { const LibraryWordEntry({required this.word,required this.isFavorite,required this.wrongCount}); final Word word; final bool isFavorite; final int wrongCount; }
class DailyStatisticsSummary { const DailyStatisticsSummary({required this.date,required this.newWords,required this.reviews,required this.correct,required this.wrong,required this.durationMs}); final DateTime date; final int newWords,reviews,correct,wrong,durationMs; }

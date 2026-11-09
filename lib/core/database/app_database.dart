import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import '../text/cloze_target.dart';
import 'backup_limits.dart';
import '../../services/fsrs_service.dart';
import 'missing_meaning.dart';
import 'ai_backup_validation.dart';

part 'app_database.g.dart';
part 'learning_extensions.dart';
part 'backup_snapshot.dart';

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

class RecoverySnapshots extends Table {
  IntColumn get id => integer()();
  TextColumn get payload => text()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('AiSuggestionRecord')
class AiSuggestions extends Table {
  TextColumn get id => text()();
  IntColumn get wordId => integer()();
  TextColumn get originalSnapshot => text()();
  TextColumn get cacheKey => text()();
  TextColumn get taskType => text()();
  TextColumn get context => text()();
  TextColumn get payload => text()();
  TextColumn get savedFields => text().withDefault(const Constant('[]'))();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('AiTaskRecord')
class AiTasks extends Table {
  TextColumn get id => text()();
  TextColumn get context => text()();
  TextColumn get status => text().withDefault(const Constant('paused'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('AiTaskItemRecord')
class AiTaskItems extends Table {
  TextColumn get id => text()();
  TextColumn get taskId => text().references(AiTasks, #id)();
  IntColumn get wordId => integer()();
  TextColumn get originalSnapshot => text()();
  TextColumn get status => text().withDefault(const Constant('queued'))();
  TextColumn get suggestionId => text().nullable()();
  TextColumn get errorCode => text().nullable()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AiWordContents extends Table {
  IntColumn get wordId => integer()();
  TextColumn get field => text()();
  TextColumn get value => text()();
  TextColumn get requestId => text()();
  TextColumn get model => text()();
  TextColumn get promptVersion => text()();
  TextColumn get originalSnapshot => text()();
  DateTimeColumn get generatedAt => dateTime()();
  DateTimeColumn get confirmedAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {wordId, field};
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
    RecoverySnapshots,
    AiSuggestions,
    AiTasks,
    AiTaskItems,
    AiWordContents,
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
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await _ensureStudyCardsDueIndex();
    },
    // Retire only obsolete cloud markers; keep every local learning table.
    beforeOpen: (_) => customStatement(
      "DELETE FROM app_settings WHERE substr(key,1,6) = 'cloud_'",
    ),
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.createTable(appSettings);
      }
      if (from < 3) await migrator.createTable(recoverySnapshots);
      if (from < 4) {
        await migrator.createTable(aiSuggestions);
        await migrator.createTable(aiTasks);
        await migrator.createTable(aiTaskItems);
        await migrator.createTable(aiWordContents);
      }
      if (from < 5) await _ensureStudyCardsDueIndex();
    },
  );

  Future<void> _ensureStudyCardsDueIndex() => customStatement(
    'CREATE INDEX IF NOT EXISTS idx_study_cards_due ON study_cards (due)',
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
    final rows =
        await (select(appSettings)..where(
              (row) => row.key.isIn(const [
                DailyPlanSettings.newWordsKey,
                DailyPlanSettings.reviewsKey,
              ]),
            ))
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
      await (delete(appSettings)..where(
            (row) => row.key.isIn(const [
              'study_round_day',
              'study_round_baseline',
              'study_round_target',
            ]),
          ))
          .go();
    });
  }

  Future<String?> loadSetting(String key) async {
    final row = await (select(
      appSettings,
    )..where((item) => item.key.equals(key))).getSingleOrNull();
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
    final statistics = await (select(
      dailyStatistics,
    )..where((row) => row.date.equals(day))).getSingleOrNull();
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
        ? int.tryParse(await loadSetting('study_round_target') ?? '') ??
              progress.settings.newWordsPerDay
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
      await saveSetting(
        'study_round_day',
        _dailyStatKey(localNow).toIso8601String(),
      );
      await saveSetting(
        'study_round_baseline',
        progress.newWordsDone.toString(),
      );
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
      final dueQuery =
          select(words).join([
              innerJoin(studyCards, studyCards.wordId.equalsExp(words.id)),
              if (bookId != null)
                innerJoin(
                  wordBookWords,
                  wordBookWords.wordId.equalsExp(words.id) &
                      wordBookWords.wordBookId.equals(bookId),
                ),
            ])
            ..where(
              studyCards.due.isSmallerOrEqualValue(nowUtc) &
                  const Constant<bool>(true),
            )
            ..orderBy([OrderingTerm.asc(studyCards.due)])
            ..limit(1);
      final dueRow = await dueQuery.getSingleOrNull();
      if (dueRow != null) return dueRow.readTable(words);
    }

    final round = await loadStudyRoundProgress(localNow);
    if (progress.newWordsDone >= round.baseline + round.target) return null;

    final newQuery =
        select(words).join([
            leftOuterJoin(studyCards, studyCards.wordId.equalsExp(words.id)),
            if (bookId != null)
              innerJoin(
                wordBookWords,
                wordBookWords.wordId.equalsExp(words.id) &
                    wordBookWords.wordBookId.equals(bookId),
              ),
          ])
          ..where(studyCards.id.isNull() & const Constant<bool>(true))
          ..orderBy([OrderingTerm.asc(words.id)])
          ..limit(1);
    final newRow = await newQuery.getSingleOrNull();
    return newRow?.readTable(words);
  }

  Future<List<WordBook>> loadWordBooks() =>
      (select(wordBooks)..orderBy([(row) => OrderingTerm.asc(row.id)])).get();

  Future<HomeCounts> loadScopedStudyCounts(int? bookId) async {
    final scope = bookId == null
        ? '1=1'
        : 'EXISTS (SELECT 1 FROM word_book_words b WHERE b.word_id=w.id AND b.word_book_id=?)';
    final variables = bookId == null
        ? <Variable>[]
        : <Variable>[Variable<int>(bookId)];
    final fresh = await customSelect(
      'SELECT COUNT(*) AS amount FROM words w WHERE $scope AND NOT EXISTS '
      '(SELECT 1 FROM study_cards s WHERE s.word_id=w.id)',
      variables: variables,
      readsFrom: {words, wordBookWords, studyCards},
    ).getSingle();
    return HomeCounts(
      due: 0,
      newWords: fresh.read<int>('amount'),
      completed: 0,
    );
  }

  Future<StudyCard?> cardForWord(int wordId) {
    return (select(
      studyCards,
    )..where((row) => row.wordId.equals(wordId))).getSingleOrNull();
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
    bool enrichExisting = false,
  }) {
    return transaction(
      () => _writeWords(
        wordBookId: wordBookId,
        drafts: drafts,
        source: source,
        enrichExisting: enrichExisting,
      ),
    );
  }

  Future<ImportWriteResult?> importWordBookIfMissing({
    required String name,
    required String sourceFileName,
    required List<WordDraft> drafts,
  }) {
    return transaction(() async {
      final existingBook =
          await (select(wordBooks)
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
        (draft.partOfSpeech?.trim().isEmpty ?? true)) {
      throw const FormatException('请填写韩语、中文释义和词性');
    }
    final existing =
        await (select(words)..where(
              (word) =>
                  word.normalizedKorean.equals(draft.normalizedKorean) &
                  word.normalizedBaseForm.equals(draft.normalizedBaseForm),
            ))
            .getSingleOrNull();
    if (existing != null) {
      throw const FormatException('这个单词已存在，请在词库中编辑');
    }
    const source = 'manual://words';
    final book = await (select(
      wordBooks,
    )..where((item) => item.sourceFileName.equals(source))).getSingleOrNull();
    final now = DateTime.now().toUtc();
    final bookId =
        book?.id ??
        await into(wordBooks).insert(
          WordBooksCompanion.insert(
            name: '手动录入',
            sourceFileName: const Value(source),
            createdAt: now,
            updatedAt: now,
          ),
        );
    final wordId = await into(words).insert(draft.toCompanion(source: '手动录入'));
    await into(wordBookWords).insert(
      WordBookWordsCompanion.insert(
        wordBookId: bookId,
        wordId: wordId,
        sortOrder: wordId,
      ),
    );
    return wordId;
  });

  /// Looks up only the incoming keys, in chunks. Never scans the whole words table.
  Future<Map<(String, String), Word>> _wordsForDrafts(
    List<WordDraft> drafts,
  ) async {
    final found = <(String, String), Word>{};
    for (var offset = 0; offset < drafts.length; offset += 200) {
      final keys = drafts
          .skip(offset)
          .take(200)
          .map((draft) => draft.normalizedKorean)
          .toSet()
          .toList();
      if (keys.isEmpty) continue;
      final rows = await (select(
        words,
      )..where((word) => word.normalizedKorean.isIn(keys))).get();
      for (final row in rows) {
        found[(row.normalizedKorean, row.normalizedBaseForm)] = row;
      }
    }
    return found;
  }

  Future<ImportWriteResult> _writeWords({
    required int wordBookId,
    required List<WordDraft> drafts,
    required String source,
    bool enrichExisting = false,
  }) async {
    final known = await _wordsForDrafts(drafts);
    final additions = <WordsCompanion>[];
    final insertedKeys = <(String, String)>{};
    for (final draft in drafts) {
      final key = (draft.normalizedKorean, draft.normalizedBaseForm);
      if (known.containsKey(key) || !insertedKeys.add(key)) continue;
      additions.add(draft.toCompanion(source: source));
    }
    for (var offset = 0; offset < additions.length; offset += 400) {
      await batch(
        (batch) => batch.insertAll(words, additions.skip(offset).take(400)),
      );
    }
    if (additions.isNotEmpty) {
      known
        ..clear()
        ..addAll(await _wordsForDrafts(drafts));
    }
    final links = <WordBookWordsCompanion>[];
    final enriched = <int>{};
    for (var index = 0; index < drafts.length; index++) {
      final draft = drafts[index];
      final key = (draft.normalizedKorean, draft.normalizedBaseForm);
      final existing = known[key];
      if (existing == null) continue;
      links.add(
        WordBookWordsCompanion.insert(
          wordBookId: wordBookId,
          wordId: existing.id,
          sortOrder: index,
        ),
      );
      if (!enrichExisting ||
          insertedKeys.contains(key) ||
          !enriched.add(existing.id)) {
        continue;
      }
      await (update(words)..where((word) => word.id.equals(existing.id))).write(
        WordsCompanion(
          meaningZh: isMissingMeaning(existing.meaningZh)
              ? Value(draft.meaningZh)
              : const Value.absent(),
          partOfSpeech: existing.partOfSpeech == null
              ? Value(_nullable(draft.partOfSpeech))
              : const Value.absent(),
          exampleKo: existing.exampleKo == null
              ? Value(_nullable(draft.exampleKo))
              : const Value.absent(),
          exampleZh: existing.exampleZh == null
              ? Value(_nullable(draft.exampleZh))
              : const Value.absent(),
          tags: existing.tags == null
              ? Value(_nullable(draft.tags))
              : const Value.absent(),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
    }
    for (var offset = 0; offset < links.length; offset += 400) {
      await batch(
        (batch) => batch.insertAll(
          wordBookWords,
          links.skip(offset).take(400),
          mode: InsertMode.insertOrReplace,
        ),
      );
    }
    return ImportWriteResult(
      inserted: additions.length,
      reused: drafts.length - additions.length,
    );
  }

  Future<ReviewWriteResult> persistReview({
    required int wordId,
    required String submissionToken,
    required int rating,
    required DateTime reviewedAt,
    required int durationMs,
    required DateTime localDay,
    required Map<String, Object?> cardMap,
    required Map<String, Object?> reviewLogMap,
    SessionOptions? session,
  }) {
    return transaction(() async {
      final undo = await captureReviewUndo(wordId, localDay, session);
      final previous = await cardForWord(wordId);
      final now = reviewedAt.toUtc();
      final due = _dateTime(cardMap['due']) ?? now;
      final isNewWord = previous == null;
      // Learning and relearning steps stay inside the day and do not spend the review cap.
      final isShortTerm =
          previous != null && (previous.state == 1 || previous.state == 3);
      final countsAsReview = previous != null && !isShortTerm;
      final isWrong = rating == 1;
      final lapses =
          (previous?.lapses ?? 0) +
          (previous != null && previous.state == 2 && isWrong ? 1 : 0);
      final becameLeech =
          lapses >= leechLapseThreshold &&
          previous != null &&
          previous.state == 2 &&
          isWrong;
      final companion = StudyCardsCompanion(
        wordId: Value(wordId),
        state: Value(_integer(cardMap['state'])),
        due: Value(due),
        stability: Value(_double(cardMap['stability'])),
        difficulty: Value(_double(cardMap['difficulty'])),
        elapsedDays: Value(_integer(cardMap['elapsed_days'])),
        scheduledDays: Value(_integer(cardMap['scheduled_days'])),
        reps: Value(_integer(cardMap['reps'])),
        lapses: Value(lapses),
        lastReview: Value(_dateTime(cardMap['last_review'])),
        fsrsJson: Value(jsonEncode(cardMap)),
        createdAt: Value(previous?.createdAt ?? now),
        updatedAt: Value(now),
      );
      if (previous == null) {
        await into(studyCards).insert(companion);
      } else {
        await (update(
          studyCards,
        )..where((row) => row.wordId.equals(wordId))).write(companion);
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
      final statistics = await (select(
        dailyStatistics,
      )..where((row) => row.date.equals(day))).getSingleOrNull();
      if (statistics == null) {
        await into(dailyStatistics).insert(
          DailyStatisticsCompanion.insert(
            date: day,
            newWords: Value(isNewWord ? 1 : 0),
            reviewWords: Value(countsAsReview ? 1 : 0),
            correctCount: Value(isWrong ? 0 : 1),
            wrongCount: Value(isWrong ? 1 : 0),
            studyDurationMs: Value(durationMs),
          ),
        );
      } else {
        await (update(
          dailyStatistics,
        )..where((row) => row.date.equals(day))).write(
          DailyStatisticsCompanion(
            newWords: Value(statistics.newWords + (isNewWord ? 1 : 0)),
            reviewWords: Value(
              statistics.reviewWords + (countsAsReview ? 1 : 0),
            ),
            correctCount: Value(statistics.correctCount + (isWrong ? 0 : 1)),
            wrongCount: Value(statistics.wrongCount + (isWrong ? 1 : 0)),
            studyDurationMs: Value(statistics.studyDurationMs + durationMs),
          ),
        );
      }
      await customStatement(
        'INSERT INTO user_words (word_id,is_favorite,is_difficult,correct_count,wrong_count,last_seen_at) VALUES (?,0,?,?,?,?) '
        'ON CONFLICT(word_id) DO UPDATE SET is_difficult=CASE WHEN excluded.is_difficult=1 THEN 1 ELSE user_words.is_difficult END, '
        'correct_count=user_words.correct_count+excluded.correct_count, wrong_count=user_words.wrong_count+excluded.wrong_count, last_seen_at=excluded.last_seen_at',
        [
          wordId,
          isWrong ? 1 : 0,
          isWrong ? 0 : 1,
          isWrong ? 1 : 0,
          now.millisecondsSinceEpoch ~/ 1000,
        ],
      );
      await finishLearningReview(
        wordId,
        rating,
        localDay,
        submissionToken,
        undo,
        session,
      );
      if (becameLeech) await saveSetting('word_status:$wordId', 'suspended');
      return ReviewWriteResult(leechSuspended: becameLeech, lapses: lapses);
    });
  }

  ({String where, List<Variable> variables}) _libraryClause({
    required String query,
    required LibraryFilter filter,
    int? bookId,
  }) {
    final normalized = normalizeLookup(query);
    final where = <String>['1=1'];
    final variables = <Variable>[];
    if (normalized.isNotEmpty) {
      where.add(
        '(lower(w.korean) LIKE ? OR lower(w.meaning_zh) LIKE ? OR lower(w.base_form) LIKE ? OR lower(coalesce(w.tags, \'\')) LIKE ? OR lower(coalesce(w.part_of_speech, \'\')) LIKE ?)',
      );
      final like = '%$normalized%';
      variables.addAll([for (var i = 0; i < 5; i++) Variable<String>(like)]);
    }
    switch (filter) {
      case LibraryFilter.favorites:
        where.add('u.is_favorite = 1');
      case LibraryFilter.wrong:
        where.add('u.is_difficult = 1');
      case LibraryFilter.missingMeaning:
        final list = missingMeaningPlaceholders
            .map((item) => "'${item.replaceAll("'", "''")}'")
            .join(',');
        where.add(
          "replace(replace(lower(trim(w.meaning_zh)), ' ', ''), '　', '') IN ($list) OR trim(w.meaning_zh) = ''",
        );
      case LibraryFilter.all:
        break;
    }
    if (bookId != null) {
      where.add(
        'EXISTS (SELECT 1 FROM word_book_words b WHERE b.word_id = w.id AND b.word_book_id = ?)',
      );
      variables.add(Variable<int>(bookId));
    }
    return (where: where.join(' AND '), variables: variables);
  }

  String get _libraryFrom =>
      'FROM words w LEFT JOIN user_words u ON u.word_id = w.id';

  Future<int> countLibraryWords({
    required String query,
    required LibraryFilter filter,
    int? bookId,
  }) async {
    final clause = _libraryClause(query: query, filter: filter, bookId: bookId);
    final row = await customSelect(
      'SELECT COUNT(*) AS amount $_libraryFrom WHERE ${clause.where}',
      variables: clause.variables,
      readsFrom: {words, userWords, wordBookWords},
    ).getSingle();
    return row.read<int>('amount');
  }

  Future<List<LibraryWordEntry>> searchLibraryWords({
    required String query,
    required LibraryFilter filter,
    int? bookId,
    int? limit,
    int offset = 0,
  }) async {
    final clause = _libraryClause(query: query, filter: filter, bookId: bookId);
    final variables = [...clause.variables];
    var sql =
        'SELECT w.id $_libraryFrom WHERE ${clause.where} ORDER BY w.korean, w.id';
    if (limit != null) {
      sql += ' LIMIT ? OFFSET ?';
      variables.addAll([Variable<int>(limit), Variable<int>(offset)]);
    }
    final idRows = await customSelect(
      sql,
      variables: variables,
      readsFrom: {words, userWords, wordBookWords},
    ).get();
    final ids = [for (final row in idRows) row.read<int>('id')];
    if (ids.isEmpty) return const [];
    final loaded = await (select(
      words,
    )..where((word) => word.id.isIn(ids))).get();
    final users = await (select(
      userWords,
    )..where((row) => row.wordId.isIn(ids))).get();
    final byId = {for (final word in loaded) word.id: word};
    final userById = {for (final row in users) row.wordId: row};
    return [
      for (final id in ids)
        if (byId[id] != null)
          LibraryWordEntry(
            word: byId[id]!,
            isFavorite: userById[id]?.isFavorite ?? false,
            wrongCount: userById[id]?.wrongCount ?? 0,
          ),
    ];
  }

  Future<void> setFavorite(int id, bool value) => customStatement(
    'INSERT INTO user_words (word_id, is_favorite, is_difficult, correct_count, wrong_count) VALUES (?, ?, 0, 0, 0) '
    'ON CONFLICT(word_id) DO UPDATE SET is_favorite = excluded.is_favorite',
    [id, value ? 1 : 0],
  );

  Future<void> updateWord({
    required int wordId,
    required String korean,
    required String meaningZh,
    String? partOfSpeech,
    String? exampleKo,
    String? exampleZh,
    String? tags,
    String? note,
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
        exampleKo: exampleKo == null
            ? const Value.absent()
            : Value(_nullable(exampleKo)),
        exampleZh: exampleZh == null
            ? const Value.absent()
            : Value(_nullable(exampleZh)),
        tags: tags == null ? const Value.absent() : Value(_nullable(tags)),
        note: note == null ? const Value.absent() : Value(_nullable(note)),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> deleteWord(int id) => transaction(() async {
    await (delete(aiWordContents)..where((r) => r.wordId.equals(id))).go();
    await (delete(aiSuggestions)..where((r) => r.wordId.equals(id))).go();
    await (delete(aiTaskItems)..where((r) => r.wordId.equals(id))).go();
    await (delete(appSettings)..where(
          (r) => r.key.isIn([
            'word_status:$id',
            'word_forms:$id',
            'correct_streak:$id',
          ]),
        ))
        .go();
    final undo = await loadSetting('last_review_undo');
    if (undo != null && (jsonDecode(undo) as Map)['wordId'] == id) {
      await saveSetting('last_review_undo', null);
    }
    await (delete(reviewLogs)..where((r) => r.wordId.equals(id))).go();
    await (delete(studyCards)..where((r) => r.wordId.equals(id))).go();
    await (delete(userWords)..where((r) => r.wordId.equals(id))).go();
    await (delete(wordBookWords)..where((r) => r.wordId.equals(id))).go();
    await (delete(words)..where((r) => r.id.equals(id))).go();
  });

  Future<List<DailyStatisticsSummary>> loadRecentStatistics(
    DateTime now, {
    int days = 7,
  }) async {
    final today = DateTime.utc(now.year, now.month, now.day),
        start = DateTime.utc(
          now.year,
          now.month,
          now.day,
        ).subtract(Duration(days: days - 1));
    final rows =
        await (select(dailyStatistics)
              ..where(
                (r) =>
                    r.date.isBiggerOrEqualValue(start) &
                    r.date.isSmallerOrEqualValue(today),
              )
              ..orderBy([(r) => OrderingTerm.asc(r.date)]))
            .get();
    // Drift decodes SQLite timestamps as local DateTime objects. DateTime
    // equality distinguishes UTC and local objects even for the same instant.
    // Use the stored instant as the key so existing rows match in every timezone.
    final values = {for (final r in rows) r.date.millisecondsSinceEpoch: r};
    return List.generate(days, (i) {
      final d = start.add(Duration(days: i)),
          r = values[d.millisecondsSinceEpoch];
      return DailyStatisticsSummary(
        date: d,
        newWords: r?.newWords ?? 0,
        reviews: r?.reviewWords ?? 0,
        correct: r?.correctCount ?? 0,
        wrong: r?.wrongCount ?? 0,
        durationMs: r?.studyDurationMs ?? 0,
      );
    });
  }
}

class ReviewWriteResult {
  const ReviewWriteResult({required this.leechSuspended, required this.lapses});
  final bool leechSuspended;
  final int lapses;
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
  int get totalLimit => settings.newWordsPerDay + settings.reviewsPerDay;
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

enum LibraryFilter { all, favorites, wrong, missingMeaning }

class LibraryWordEntry {
  const LibraryWordEntry({
    required this.word,
    required this.isFavorite,
    required this.wrongCount,
  });
  final Word word;
  final bool isFavorite;
  final int wrongCount;
}

class DailyStatisticsSummary {
  const DailyStatisticsSummary({
    required this.date,
    required this.newWords,
    required this.reviews,
    required this.correct,
    required this.wrong,
    required this.durationMs,
  });
  final DateTime date;
  final int newWords, reviews, correct, wrong, durationMs;
}

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

  Future<Word?> nextStudyWord(
    DateTime nowUtc, {
    required DateTime localNow,
  }) async {
    final progress = await loadDailyPlanProgress(localNow);

    if (progress.reviewsDone < progress.settings.reviewsPerDay) {
      final dueQuery = select(words).join([
        innerJoin(studyCards, studyCards.wordId.equalsExp(words.id)),
      ])
        ..where(studyCards.due.isSmallerOrEqualValue(nowUtc))
        ..orderBy([OrderingTerm.asc(studyCards.due)])
        ..limit(1);
      final dueRow = await dueQuery.getSingleOrNull();
      if (dueRow != null) return dueRow.readTable(words);
    }

    if (progress.newWordsDone >= progress.settings.newWordsPerDay) return null;

    final newQuery = select(words).join([
      leftOuterJoin(studyCards, studyCards.wordId.equalsExp(words.id)),
    ])
      ..where(studyCards.id.isNull())
      ..orderBy([OrderingTerm.asc(words.id)])
      ..limit(1);
    final newRow = await newQuery.getSingleOrNull();
    return newRow?.readTable(words);
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
  Future<List<LibraryWordEntry>> searchLibraryWords({required String query, required LibraryFilter filter}) async {
    final q = normalizeLookup(query);
    final rows = await customSelect(
      'SELECT w.*, COALESCE(u.is_favorite, 0) AS favorite, COALESCE(u.wrong_count, 0) AS wrong_count '
      'FROM words w LEFT JOIN user_words u ON u.word_id = w.id '
      'WHERE (? = \'\' OR lower(w.korean) LIKE ? OR lower(w.meaning_zh) LIKE ? OR lower(w.base_form) LIKE ?) '
      'AND (? = 0 OR COALESCE(u.is_favorite, 0) = 1) AND (? = 0 OR COALESCE(u.wrong_count, 0) > 0) '
      'ORDER BY w.korean LIMIT 1000',
      variables: [Variable<String>(q), Variable<String>('%$q%'), Variable<String>('%$q%'), Variable<String>('%$q%'),
        Variable<int>(filter == LibraryFilter.favorites ? 1 : 0), Variable<int>(filter == LibraryFilter.wrong ? 1 : 0)],
      readsFrom: {words, userWords},
    ).get();
    return rows.map((r) => LibraryWordEntry(word: Word.fromData(r.data, this),
      isFavorite: r.read<int>('favorite') != 0, wrongCount: r.read<int>('wrong_count'))).toList();
  }

  Future<void> setFavorite(int id, bool value) => customStatement(
    'INSERT INTO user_words (word_id, is_favorite, is_difficult, correct_count, wrong_count) VALUES (?, ?, 0, 0, 0) '
    'ON CONFLICT(word_id) DO UPDATE SET is_favorite = excluded.is_favorite', [id, value ? 1 : 0]);

  Future<void> updateWord({required int wordId, required String korean, required String meaningZh}) async {
    final k = korean.trim(), m = meaningZh.trim();
    if (k.isEmpty || m.isEmpty) throw ArgumentError('韩语词条和中文释义不能为空');
    await (update(words)..where((w) => w.id.equals(wordId))).write(WordsCompanion(
      korean: Value(k), normalizedKorean: Value(normalizeLookup(k)), meaningZh: Value(m),
      updatedAt: Value(DateTime.now().toUtc())));
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
        newWordsPerDay: newWordsPerDay.clamp(1, 100).toInt(),
        reviewsPerDay: reviewsPerDay.clamp(1, 500).toInt(),
      );
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

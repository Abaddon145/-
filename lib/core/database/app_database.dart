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

@DriftDatabase(
  tables: [
    Words,
    WordBooks,
    WordBookWords,
    StudyCards,
    ReviewLogs,
    UserWords,
    DailyStatistics,
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
  int get schemaVersion => 1;

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

  Future<Word?> nextStudyWord(DateTime nowUtc) async {
    final dueQuery = select(words).join([
      innerJoin(studyCards, studyCards.wordId.equalsExp(words.id)),
    ])
      ..where(studyCards.due.isSmallerOrEqualValue(nowUtc))
      ..orderBy([OrderingTerm.asc(studyCards.due)])
      ..limit(1);
    final dueRow = await dueQuery.getSingleOrNull();
    if (dueRow != null) return dueRow.readTable(words);

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
    });
  }
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

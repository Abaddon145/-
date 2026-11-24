import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/core/database/app_database.dart';
import 'package:korean_memo/core/language/learning_language.dart';
import 'package:korean_memo/features/import/data/bundled_word_seed_service.dart';
import 'package:korean_memo/features/study/data/study_repository.dart';
import 'package:korean_memo/features/study/domain/providers.dart';
import 'package:korean_memo/features/study/presentation/study_controller.dart';
import 'package:korean_memo/features/study/presentation/study_page.dart';
import 'package:korean_memo/services/fsrs_service.dart';

const _emptySeed = BundledSeedResult(
  importedBooks: 0,
  existingBooks: 0,
  inserted: 0,
  reused: 0,
  bundledEntries: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'first open reads today for Korean and English without a stats row',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await database.addManualWord(
        const WordDraft(korean: '하늘', meaningZh: '天', partOfSpeech: '名词'),
      );
      await database.addManualWord(
        const WordDraft(korean: 'sky', meaningZh: '天空'),
        language: 'en',
      );
      final now = DateTime.now();
      final korean = await database.nextTrainingWord(
        const SessionOptions(language: 'ko'),
        now,
      );
      final english = await database.nextTrainingWord(
        const SessionOptions(language: 'en'),
        now,
      );
      expect(korean?.headword, '하늘');
      expect(english?.headword, 'sky');
      expect((await database.loadDailyPlanProgress(now, 'ko')).totalDone, 0);
      expect((await database.loadDailyPlanProgress(now, 'en')).totalDone, 0);
      await _expectTodayLoads(database, 'en', 'sky');
    },
  );

  test('a null saved session does not crash the daily queue', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.addManualWord(
      const WordDraft(korean: '하늘', meaningZh: '天', partOfSpeech: '名词'),
    );
    final now = DateTime.now();
    await database.saveSetting(
      const SessionOptions().storageKey,
      jsonEncode({
        'day': dayKey(now),
        'done': null,
        'target': null,
        'seen': null,
      }),
    );
    expect(
      (await database.nextTrainingWord(const SessionOptions(), now))?.headword,
      '하늘',
    );
  });

  test('schema 8 with today already studied upgrades into 今日学习', () async {
    final database = await _reopen(_prepareSchema8);
    final now = DateTime.now();
    final rows = await database.select(database.dailyStatistics).get();
    expect(rows, isNotEmpty);
    for (final row in rows) {
      expect(row.firstAttemptCount, row.correctCount + row.wrongCount);
      expect(row.firstCorrectCount, row.correctCount);
    }
    expect(
      (await database.nextTrainingWord(
        const SessionOptions(language: 'ko'),
        now,
      ))?.headword,
      '하늘',
    );
    expect(
      (await database.nextTrainingWord(
        const SessionOptions(language: 'en'),
        now,
      ))?.headword,
      'sky',
    );
    await _expectTodayLoads(database, 'ko', '하늘');
    await _expectTodayLoads(database, 'en', 'sky');
  });

  test('schema 9 rows with null attempt counters can open 今日学习', () async {
    final database = await _reopen(_prepareNullCounters);
    final now = DateTime.now();
    final rows = await database.select(database.dailyStatistics).get();
    expect(rows, hasLength(2));
    for (final row in rows) {
      expect(row.firstAttemptCount, greaterThan(0));
      expect(row.firstAttemptCount, row.correctCount + row.wrongCount);
    }
    expect((await database.loadDailyPlanProgress(now, 'ko')).newWordsDone, 1);
    expect((await database.loadDailyPlanProgress(now, 'en')).newWordsDone, 1);
    await database.saveDailyPlanSettings(
      const DailyPlanSettings(newWordsPerDay: 1, reviewsPerDay: 1),
      'ko',
    );
    expect(
      await database.nextTrainingWord(
        const SessionOptions(language: 'ko'),
        now,
      ),
      isNull,
    );
    expect(
      (await database.nextTrainingWord(
        const SessionOptions(language: 'en'),
        now,
      ))?.headword,
      'sky',
    );
    await _expectTodayLoads(database, 'en', 'sky');
  });

  testWidgets('今日学习 renders after a null-counter upgrade', (tester) async {
    final database = await tester.runAsync(() => _reopen(_prepareNullCounters));
    await _pumpToday(tester, database!);
    expect(find.text('今日学习'), findsOneWidget);
    expect(find.textContaining('读取失败'), findsNothing);
    expect(find.text('하늘'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English 今日学习 renders after a null-counter upgrade', (
    tester,
  ) async {
    final database = await tester.runAsync(() async {
      final opened = await _reopen(_prepareNullCounters);
      await opened.saveSetting(activeLanguageSettingKey, 'en');
      return opened;
    });
    await _pumpToday(tester, database!, language: 'en');
    expect(find.text('今日学习'), findsOneWidget);
    expect(find.textContaining('读取失败'), findsNothing);
    expect(find.text('sky'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('first open of 今日学习 shows the first Korean card', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.addManualWord(
      const WordDraft(korean: '하늘', meaningZh: '天', partOfSpeech: '名词'),
    );
    await _pumpToday(tester, database);
    expect(find.text('今日学习'), findsOneWidget);
    expect(find.textContaining('读取失败'), findsNothing);
    expect(find.text('하늘'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _expectTodayLoads(
  AppDatabase database,
  String language,
  String headword,
) async {
  final controller = StudyController(
    StudyRepository(
      database,
      FsrsService(),
      options: SessionOptions(language: language),
    ),
  );
  addTearDown(controller.dispose);
  await controller.load();
  expect(controller.state.error, isNull);
  expect(controller.state.word?.headword, headword);
}

Future<AppDatabase> _reopen(
  Future<void> Function(AppDatabase database) prepare,
) async {
  final directory = await Directory.systemTemp.createTemp('today-study');
  addTearDown(() => directory.delete(recursive: true));
  final file = File('${directory.path}/memo.sqlite');
  final created = AppDatabase(NativeDatabase(file));
  await _seedToday(created);
  await prepare(created);
  await created.close();
  final upgraded = AppDatabase(NativeDatabase(file));
  addTearDown(upgraded.close);
  return upgraded;
}

Future<void> _seedToday(AppDatabase database) async {
  final now = DateTime.now();
  await database.addManualWord(
    const WordDraft(korean: '하늘', meaningZh: '天', partOfSpeech: '名词'),
  );
  final korean = await database.addManualWord(
    const WordDraft(korean: '학교', meaningZh: '学校', partOfSpeech: '名词'),
  );
  await database.addManualWord(
    const WordDraft(korean: 'sky', meaningZh: '天空'),
    language: 'en',
  );
  final english = await database.addManualWord(
    const WordDraft(korean: 'book', meaningZh: '书'),
    language: 'en',
  );
  await _rate(database, korean, now);
  await _rate(database, english, now);
}

Future<void> _rate(AppDatabase database, int id, DateTime now) {
  return database.persistReview(
    wordId: id,
    submissionToken: 'today-$id',
    rating: 3,
    reviewedAt: now.toUtc(),
    localDay: now,
    durationMs: 1200,
    cardMap: {
      'state': 2,
      'due': now.toUtc().add(const Duration(days: 2)).toIso8601String(),
      'reps': 1,
      'stability': 4,
      'difficulty': 5,
    },
    reviewLogMap: const {},
  );
}

Future<void> _prepareSchema8(AppDatabase database) async {
  await database.customStatement('PRAGMA foreign_keys = OFF');
  await database.customStatement('''
    CREATE TABLE daily_statistics__v8 (
      date INTEGER NOT NULL,
      new_words INTEGER NOT NULL DEFAULT 0,
      review_words INTEGER NOT NULL DEFAULT 0,
      correct_count INTEGER NOT NULL DEFAULT 0,
      wrong_count INTEGER NOT NULL DEFAULT 0,
      study_duration_ms INTEGER NOT NULL DEFAULT 0,
      language TEXT NOT NULL DEFAULT 'ko',
      PRIMARY KEY (date, language)
    )
  ''');
  await database.customStatement('''
    INSERT INTO daily_statistics__v8 (
      date, new_words, review_words, correct_count, wrong_count,
      study_duration_ms, language
    )
    SELECT date, new_words, review_words, correct_count, wrong_count,
      study_duration_ms, language
    FROM daily_statistics
  ''');
  await database.customStatement('DROP TABLE daily_statistics');
  await database.customStatement(
    'ALTER TABLE daily_statistics__v8 RENAME TO daily_statistics',
  );
  await database.customStatement('DROP TABLE IF EXISTS atlas_entries');
  await database.customStatement(
    'DROP INDEX IF EXISTS idx_word_books_stable_id',
  );
  await database.customStatement(
    'ALTER TABLE word_books DROP COLUMN stable_id',
  );
  await database.customStatement('PRAGMA user_version = 8');
  await database.customStatement('PRAGMA foreign_keys = ON');
}

Future<void> _prepareNullCounters(AppDatabase database) async {
  await database.customStatement('PRAGMA foreign_keys = OFF');
  await database.customStatement('''
    CREATE TABLE daily_statistics__null (
      date INTEGER NOT NULL,
      new_words INTEGER NOT NULL DEFAULT 0,
      review_words INTEGER NOT NULL DEFAULT 0,
      correct_count INTEGER NOT NULL DEFAULT 0,
      wrong_count INTEGER NOT NULL DEFAULT 0,
      study_duration_ms INTEGER NOT NULL DEFAULT 0,
      language TEXT NOT NULL DEFAULT 'ko',
      first_correct_count INTEGER,
      first_attempt_count INTEGER,
      PRIMARY KEY (date, language)
    )
  ''');
  await database.customStatement('''
    INSERT INTO daily_statistics__null (
      date, new_words, review_words, correct_count, wrong_count,
      study_duration_ms, language, first_correct_count, first_attempt_count
    )
    SELECT date, new_words, review_words, correct_count, wrong_count,
      study_duration_ms, language, NULL, NULL
    FROM daily_statistics
  ''');
  await database.customStatement('DROP TABLE daily_statistics');
  await database.customStatement(
    'ALTER TABLE daily_statistics__null RENAME TO daily_statistics',
  );
  await database.customStatement('PRAGMA user_version = 9');
  await database.customStatement('PRAGMA foreign_keys = ON');
}

Future<void> _pumpToday(
  WidgetTester tester,
  AppDatabase database, {
  String? language,
}) async {
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(database),
      bundledWordSeedProvider.overrideWith((ref) async => _emptySeed),
    ],
  );
  addTearDown(container.dispose);
  if (language != null) {
    await container.read(activeLanguageProvider.notifier).reload();
  }
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child ?? const SizedBox.shrink(),
        ),
        home: const StudyPage(),
      ),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.textContaining('读取失败').evaluate().isNotEmpty) break;
    if (find.text('하늘').evaluate().isNotEmpty ||
        find.text('sky').evaluate().isNotEmpty ||
        find.text('本轮完成，或暂时没有符合条件的词').evaluate().isNotEmpty) {
      break;
    }
  }
}

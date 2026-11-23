import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/core/database/app_database.dart';
import 'package:korean_memo/features/statistics/data/language_comparison.dart';
import 'package:korean_memo/features/statistics/domain/providers.dart';
import 'package:korean_memo/features/statistics/presentation/statistics_page.dart';
import 'package:korean_memo/features/study/domain/providers.dart';

void main() {
  test('mastery and daily totals stay split by language', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.now();
    final ko = await db.addManualWord(
      const WordDraft(korean: '가다', meaningZh: '去', partOfSpeech: '动词'),
    );
    final en = await db.addManualWord(
      const WordDraft(korean: 'sky', meaningZh: '天空'),
      language: 'en',
    );
    await db.persistReview(
      wordId: ko,
      submissionToken: 'ko-mastery',
      rating: 3,
      reviewedAt: now.toUtc(),
      localDay: now,
      durationMs: 1000,
      cardMap: {
        'state': 2,
        'due': now.toUtc().toIso8601String(),
        'stability': 40,
      },
      reviewLogMap: {},
    );
    await db.persistReview(
      wordId: en,
      submissionToken: 'en-mastery',
      rating: 3,
      reviewedAt: now.toUtc(),
      localDay: now,
      durationMs: 1000,
      cardMap: {
        'state': 2,
        'due': now.toUtc().toIso8601String(),
        'stability': 3,
      },
      reviewLogMap: {},
    );
    await (db.update(
      db.dailyStatistics,
    )..where((row) => row.language.equals('ko'))).write(
      const DailyStatisticsCompanion(
        reviewWords: Value(4),
        studyDurationMs: Value(120000),
      ),
    );
    await (db.update(
      db.dailyStatistics,
    )..where((row) => row.language.equals('en'))).write(
      const DailyStatisticsCompanion(
        reviewWords: Value(2),
        studyDurationMs: Value(60000),
      ),
    );
    final mastery = await db.masteryByLanguage();
    expect(mastery['ko']!.steady, 1);
    expect(mastery['en']!.week, 1);
    final combined = await db.loadRecentStatistics(now, combineLanguages: true);
    expect(combined.last.reviews, 6);
    expect(combined.last.durationMs, 180000);
    final english = await db.loadRecentStatistics(now, language: 'en');
    expect(english.last.reviews, 2);
  });

  testWidgets('all languages shows both review totals', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    await db
        .into(db.dailyStatistics)
        .insert(
          DailyStatisticsCompanion.insert(
            date: today,
            reviewWords: const Value(4),
            studyDurationMs: const Value(120000),
            language: const Value('ko'),
          ),
        );
    await db
        .into(db.dailyStatistics)
        .insert(
          DailyStatisticsCompanion.insert(
            date: today,
            reviewWords: const Value(2),
            studyDurationMs: const Value(60000),
            language: const Value('en'),
          ),
        );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          statisticsScopeProvider.overrideWith((ref) => 'all'),
        ],
        child: const MaterialApp(home: StatisticsPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('语言对比'), findsOneWidget);
    expect(find.text('韩语复习 4 次 · 2 分钟'), findsOneWidget);
    expect(find.text('英语复习 2 次 · 1 分钟'), findsOneWidget);
    expect(find.text('全部'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

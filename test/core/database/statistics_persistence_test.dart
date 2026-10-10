import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/core/database/app_database.dart';

void main() {
  test('existing database statistics match calendar slots after timestamp decoding', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final today = DateTime(2026, 10, 10, 13);
    await db.into(db.dailyStatistics).insert(DailyStatisticsCompanion.insert(
      date: DateTime.utc(2026, 10, 10), newWords: const Value(7),
      reviewWords: const Value(3), correctCount: const Value(9),
      wrongCount: const Value(1), studyDurationMs: const Value(150000),
    ));
    await db.into(db.dailyStatistics).insert(DailyStatisticsCompanion.insert(
      date: DateTime.utc(2026, 10, 4), newWords: const Value(2),
    ));
    final days = await db.loadRecentStatistics(today);
    expect(days, hasLength(7));
    expect(days.last.newWords, 7);
    expect(days.last.reviews, 3);
    expect(days.last.correct, 9);
    expect(days.last.wrong, 1);
    expect(days.last.durationMs, 150000);
    expect(days.first.newWords, 2);
    expect(days[1].newWords, 0);
    expect((await db.loadDailyPlanProgress(today)).newWordsDone, 7);
  });

  test('rating persistence immediately updates statistics and survives backup restoration', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final restored = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    addTearDown(restored.close);
    final now = DateTime(2026, 10, 10, 0, 5);
    final id = await db.addManualWord(const WordDraft(
      korean: '하늘', meaningZh: '天空', partOfSpeech: '名词'));
    Future<void> rate(int rating, String token) => db.persistReview(
      wordId: id, submissionToken: token, rating: rating,
      reviewedAt: now.toUtc(), localDay: now, durationMs: 1500,
      cardMap: {'due': now.toUtc().toIso8601String(), 'state': 1},
      reviewLogMap: {},
    );
    await rate(3, 'first');
    final first = (await db.loadRecentStatistics(now)).last;
    expect(first.newWords, 1);
    expect(first.correct, 1);
    await rate(1, 'second');
    final second = (await db.loadRecentStatistics(now)).last;
    expect(second.newWords, 1);
    expect(second.reviews, 1);
    expect(second.correct, 1);
    expect(second.wrong, 1);
    expect(second.durationMs, 3000);
    await restored.restoreBackupSnapshot(await db.createBackupSnapshot());
    final reopened = (await restored.loadRecentStatistics(now)).last;
    expect(reopened.newWords, 1);
    expect(reopened.reviews, 1);
    expect(reopened.durationMs, 3000);
    expect((await db.loadRecentStatistics(now.add(const Duration(days: 1)))).last.newWords, 0);
    expect((await db.loadRecentStatistics(now.add(const Duration(days: 1))))[5].newWords, 1);
  });
}

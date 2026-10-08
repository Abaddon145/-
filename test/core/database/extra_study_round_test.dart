import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/core/database/app_database.dart';

void main() {
  test('new word goals above 100 survive saving and backup restoration', () async {
    final database = AppDatabase(NativeDatabase.memory());
    final restored = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    addTearDown(restored.close);
    await database.saveDailyPlanSettings(
      const DailyPlanSettings(newWordsPerDay: 350, reviewsPerDay: 100),
    );
    expect((await database.loadDailyPlanSettings()).newWordsPerDay, 350);
    await restored.restoreBackupSnapshot(await database.createBackupSnapshot());
    expect((await restored.loadDailyPlanSettings()).newWordsPerDay, 350);
  });

  test('completed daily plans support repeated extra rounds without changing the daily goal', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final now = DateTime(2026, 10, 8, 12);
    await database.addManualWord(
      const WordDraft(korean: '하늘', meaningZh: '天空', partOfSpeech: '名词'),
    );
    await database.into(database.dailyStatistics).insert(
      DailyStatisticsCompanion.insert(date: DateTime.utc(2026, 10, 8), newWords: const Value(20)),
    );
    expect(await database.nextStudyWord(now.toUtc(), localNow: now), isNull);
    await database.startExtraStudyRound(now, 150);
    final round = await database.loadStudyRoundProgress(now);
    expect(round.baseline, 20);
    expect(round.target, 150);
    expect(round.remaining, 150);
    expect(await database.nextStudyWord(now.toUtc(), localNow: now), isNotNull);
    await (database.update(database.dailyStatistics)).write(
      const DailyStatisticsCompanion(newWords: Value(170)),
    );
    expect(await database.nextStudyWord(now.toUtc(), localNow: now), isNull);
    await database.startExtraStudyRound(now, 30);
    expect((await database.loadStudyRoundProgress(now)).baseline, 170);
    expect(await database.nextStudyWord(now.toUtc(), localNow: now), isNotNull);
    expect((await database.loadDailyPlanSettings()).newWordsPerDay, 20);
    final tomorrow = await database.loadStudyRoundProgress(now.add(const Duration(days: 1)));
    expect(tomorrow.isExtra, isFalse);
    expect(tomorrow.baseline, 0);
    expect(tomorrow.target, 20);
  });

  test('extra rounds persist with backups and reject empty rounds', () async {
    final database = AppDatabase(NativeDatabase.memory());
    final restored = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    addTearDown(restored.close);
    final now = DateTime(2026, 10, 8, 12);
    await database.startExtraStudyRound(now, 200);
    await restored.restoreBackupSnapshot(await database.createBackupSnapshot());
    expect((await restored.loadStudyRoundProgress(now)).target, 200);
    await expectLater(database.startExtraStudyRound(now, 0), throwsFormatException);
    expect((await database.loadStudyRoundProgress(now)).target, 200);
  });
}

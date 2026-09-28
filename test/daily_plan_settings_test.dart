import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/core/database/app_database.dart';

void main() {
  test('daily plan settings use defaults and persist changes', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    final defaults = await database.loadDailyPlanSettings();
    expect(defaults.newWordsPerDay, DailyPlanSettings.defaultNewWords);
    expect(defaults.reviewsPerDay, DailyPlanSettings.defaultReviews);

    await database.saveDailyPlanSettings(
      const DailyPlanSettings(
        newWordsPerDay: 10,
        reviewsPerDay: 50,
      ),
    );

    final saved = await database.loadDailyPlanSettings();
    expect(saved.newWordsPerDay, 10);
    expect(saved.reviewsPerDay, 50);

    final progress = await database.loadDailyPlanProgress(
      DateTime(2026, 9, 23, 12),
    );
    expect(progress.newWordsDone, 0);
    expect(progress.reviewsDone, 0);
    expect(progress.settings.newWordsPerDay, 10);
  });

  test('daily plan settings are normalized to safe limits', () {
    final settings = const DailyPlanSettings(
      newWordsPerDay: 0,
      reviewsPerDay: 999,
    ).normalized();

    expect(settings.newWordsPerDay, 1);
    expect(settings.reviewsPerDay, 500);
  });
}

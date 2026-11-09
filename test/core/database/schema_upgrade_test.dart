import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/core/database/app_database.dart';
import 'package:korean_memo/features/statistics/domain/providers.dart';
import 'package:korean_memo/features/study/domain/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  test('upgrading schema 4 adds an index on study_cards.due', () async {
    final directory = await Directory.systemTemp.createTemp('koreanmemo-schema');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/memo.sqlite');
    final created = AppDatabase(NativeDatabase(file));
    await created.customSelect('SELECT 1').get();
    await created.customStatement('DROP INDEX IF EXISTS idx_study_cards_due');
    await created.customStatement('PRAGMA user_version = 4');
    await created.close();

    final upgraded = AppDatabase(NativeDatabase(file));
    addTearDown(upgraded.close);
    final indexes = await upgraded.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_study_cards_due'",
    ).get();
    expect(indexes, hasLength(1));
  });

  test('library pages do not return the whole table', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    for (var i = 0; i < 3; i++) {
      await database.addManualWord(WordDraft(
        korean: '단어$i',
        meaningZh: '释义$i',
        partOfSpeech: '名词',
      ));
    }
    final page = await database.searchLibraryWords(
      query: '',
      filter: LibraryFilter.all,
      limit: 1,
    );
    expect(page, hasLength(1));
    expect(
      await database.countLibraryWords(query: '', filter: LibraryFilter.all),
      3,
    );
  });

  test('deleting a word removes its AI suggestions and task items', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final id = await database.addManualWord(
      const WordDraft(korean: '삭제', meaningZh: '删除', partOfSpeech: '名词'),
    );
    final now = DateTime.utc(2026, 11, 9);
    await database.into(database.aiSuggestions).insert(AiSuggestionsCompanion.insert(
      id: 'suggestion',
      wordId: id,
      originalSnapshot: '{}',
      cacheKey: 'cache',
      taskType: 'complete',
      context: '日常',
      payload: '{}',
      createdAt: now,
    ));
    await database.into(database.aiTasks).insert(AiTasksCompanion.insert(
      id: 'task',
      context: '日常',
      createdAt: now,
      updatedAt: now,
    ));
    await database.into(database.aiTaskItems).insert(AiTaskItemsCompanion.insert(
      id: 'item',
      taskId: 'task',
      wordId: id,
      originalSnapshot: '{}',
    ));
    await database.deleteWord(id);
    expect(await database.select(database.aiSuggestions).get(), isEmpty);
    expect(await database.select(database.aiTaskItems).get(), isEmpty);
    expect(await database.select(database.words).get(), isEmpty);
  });

  test('statistics provider reads persisted daily totals', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final now = DateTime.now();
    final id = await database.addManualWord(
      const WordDraft(korean: '통계', meaningZh: '统计', partOfSpeech: '名词'),
    );
    await database.persistReview(
      wordId: id,
      submissionToken: 'stat',
      rating: 3,
      reviewedAt: now.toUtc(),
      localDay: now,
      durationMs: 1200,
      cardMap: {
        'state': 2,
        'due': now.toUtc().add(const Duration(days: 1)).toIso8601String(),
      },
      reviewLogMap: {},
    );
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(database),
    ]);
    addTearDown(container.dispose);
    final days = await container.read(recentStatisticsProvider.future);
    expect(days.last.newWords, 1);
    expect(days.last.correct, 1);
    expect(days.last.durationMs, 1200);
  });
}

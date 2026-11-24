import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/core/database/app_database.dart';
import 'package:korean_memo/features/ai/domain/ai_models.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  Future<File> file() async {
    final directory = await Directory.systemTemp.createTemp(
      'koreanmemo-repair',
    );
    addTearDown(() => directory.delete(recursive: true));
    return File('${directory.path}/memo.sqlite');
  }

  void createBrokenV6(File target) {
    final raw = sqlite3.open(target.path);
    raw.execute('''
      CREATE TABLE words (
        id INTEGER PRIMARY KEY,
        korean TEXT NOT NULL,
        normalized_korean TEXT NOT NULL,
        base_form TEXT NOT NULL DEFAULT '',
        normalized_base_form TEXT NOT NULL DEFAULT '',
        meaning_zh TEXT NOT NULL,
        pronunciation TEXT,
        part_of_speech TEXT,
        example_ko TEXT,
        example_zh TEXT,
        topik_level TEXT,
        category TEXT,
        tags TEXT,
        note TEXT,
        hanja TEXT,
        etymology TEXT,
        source TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    raw.execute(
      "INSERT INTO words (korean, normalized_korean, base_form, normalized_base_form, meaning_zh, created_at, updated_at) VALUES ('하늘', '하늘', '', '', '天', 1, 1)",
    );
    raw.execute(
      'CREATE TABLE word_books (id INTEGER PRIMARY KEY, name TEXT NOT NULL, description TEXT, source_file_name TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
    );
    raw.execute(
      'CREATE TABLE study_cards (id INTEGER PRIMARY KEY, word_id INTEGER NOT NULL UNIQUE, state INTEGER NOT NULL DEFAULT 0, due INTEGER NOT NULL, stability REAL NOT NULL DEFAULT 0, difficulty REAL NOT NULL DEFAULT 0, elapsed_days INTEGER NOT NULL DEFAULT 0, scheduled_days INTEGER NOT NULL DEFAULT 0, reps INTEGER NOT NULL DEFAULT 0, lapses INTEGER NOT NULL DEFAULT 0, last_review INTEGER, fsrs_json TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
    );
    raw.execute(
      'CREATE TABLE review_logs (id INTEGER PRIMARY KEY, word_id INTEGER NOT NULL, submission_token TEXT NOT NULL UNIQUE, rating INTEGER NOT NULL, reviewed_at INTEGER NOT NULL, state_before INTEGER NOT NULL, state_after INTEGER NOT NULL, elapsed_days INTEGER NOT NULL, scheduled_days INTEGER NOT NULL, duration_ms INTEGER NOT NULL, fsrs_review_log_json TEXT NOT NULL)',
    );
    raw.execute(
      'CREATE TABLE daily_statistics (date INTEGER PRIMARY KEY, new_words INTEGER NOT NULL DEFAULT 0, review_words INTEGER NOT NULL DEFAULT 0, correct_count INTEGER NOT NULL DEFAULT 0, wrong_count INTEGER NOT NULL DEFAULT 0, study_duration_ms INTEGER NOT NULL DEFAULT 0)',
    );
    raw.execute(
      'INSERT INTO daily_statistics (date, new_words, review_words) VALUES (1761955200, 4, 2)',
    );
    raw.execute(
      'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at INTEGER NOT NULL)',
    );
    for (final table in [
      'ai_suggestions',
      'ai_tasks',
      'ai_task_items',
      'ai_word_contents',
    ]) {
      raw.execute('CREATE TABLE $table (id INTEGER PRIMARY KEY)');
    }
    raw.execute('PRAGMA user_version = 6');
    raw.close();
  }

  test('a version 6 database without language columns is repaired', () async {
    final target = await file();
    createBrokenV6(target);
    final database = AppDatabase(NativeDatabase(target));
    addTearDown(database.close);
    final version = await database.customSelect('PRAGMA user_version').get();
    expect(version.single.read<int>('user_version'), 9);
    for (final table in [
      'words',
      'word_books',
      'study_cards',
      'review_logs',
      'daily_statistics',
      'ai_suggestions',
      'ai_tasks',
      'ai_task_items',
      'ai_word_contents',
    ]) {
      final columns = await database
          .customSelect('PRAGMA table_info($table)')
          .get();
      expect(
        columns.any((row) => row.read<String>('name') == 'language'),
        isTrue,
        reason: table,
      );
    }
    final stats = await database.select(database.dailyStatistics).get();
    expect(stats.single.language, 'ko');
    expect(stats.single.newWords, 4);
    expect(stats.single.reviewWords, 2);
    final day = stats.single.date.toUtc();
    final when = DateTime.utc(day.year, day.month, day.day);
    expect((await database.loadDailyPlanProgress(when)).newWordsDone, 4);
    expect((await database.loadDailyPlanProgress(when)).reviewsDone, 2);
    expect(
      (await database.loadRecentStatistics(when, days: 1)).single.reviews,
      2,
    );
    final word = await database.select(database.words).getSingle();
    expect(word.language, 'ko');
    expect(word.ipa, isNull);
  });

  test('English cache keys carry the language and prompt version', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final id = await database.addManualWord(
      const WordDraft(korean: 'sky', meaningZh: '天', ipa: 'skaɪ'),
      language: 'en',
    );
    final word = await (database.select(
      database.words,
    )..where((row) => row.id.equals(id))).getSingle();
    final key = aiCacheKey(word, '日常', 'explain', 'default', 1);
    expect(key.startsWith('en:en-zh-v1:'), isTrue);
    expect(aiPromptVersionFor('en'), 'en-zh-v1');
    expect(aiPromptVersionFor('ko'), aiPromptVersion);
  });
}

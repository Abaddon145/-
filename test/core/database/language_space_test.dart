import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/core/database/app_database.dart';
import 'package:korean_memo/core/language/learning_language.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  Future<File> v5File() async {
    final directory = await Directory.systemTemp.createTemp('koreanmemo-v5');
    addTearDown(() => directory.delete(recursive: true));
    return File('${directory.path}/memo.sqlite');
  }

  void createV5(File file, {bool duplicateWords = false}) {
    final raw = sqlite3.open(file.path);
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
    if (duplicateWords) {
      raw.execute(
        "INSERT INTO words (korean, normalized_korean, base_form, normalized_base_form, meaning_zh, created_at, updated_at) VALUES ('하늘2', '하늘', '', '', '天', 1, 1)",
      );
    }
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
      "INSERT INTO daily_statistics (date, new_words) VALUES (1761955200, 3)",
    );
    raw.execute(
      'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at INTEGER NOT NULL)',
    );
    raw.execute(
      "INSERT INTO app_settings (key, value, updated_at) VALUES ('checkin:2026-11-01', '2026-11-01T00:00:00.000Z', 1)",
    );
    raw.execute(
      "INSERT INTO app_settings (key, value, updated_at) VALUES ('daily_new_words', '12', 1)",
    );
    for (final table in [
      'ai_suggestions',
      'ai_tasks',
      'ai_task_items',
      'ai_word_contents',
    ]) {
      raw.execute('CREATE TABLE $table (id INTEGER PRIMARY KEY)');
    }
    raw.execute('PRAGMA user_version = 5');
    raw.close();
  }

  test('schema 5 migrates check-ins and words into Korean', () async {
    final file = await v5File();
    createV5(file);
    final database = AppDatabase(NativeDatabase(file));
    addTearDown(database.close);
    final word = await database
        .customSelect('SELECT language FROM words')
        .getSingle();
    expect(word.read<String>('language'), 'ko');
    expect(await database.loadSetting('checkin:ko:2026-11-01'), isNotNull);
    expect(await database.loadSetting('checkin:2026-11-01'), isNull);
    expect(await database.loadSetting('ko:daily_new_words'), '12');
    expect(await database.loadSetting(activeLanguageSettingKey), 'ko');
    final stats = await database.select(database.dailyStatistics).get();
    expect(stats.single.language, 'ko');
    expect(stats.single.newWords, 3);
    final day = stats.single.date.toUtc();
    final progress = await database.loadDailyPlanProgress(
      DateTime.utc(day.year, day.month, day.day),
    );
    expect(progress.newWordsDone, 3);
    final recent = await database.loadRecentStatistics(
      DateTime.utc(day.year, day.month, day.day),
      days: 1,
    );
    expect(recent.single.newWords, 3);
    final ipa = await database.customSelect('PRAGMA table_info(words)').get();
    expect(ipa.any((row) => row.read<String>('name') == 'ipa'), isTrue);
    final indexes = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE name = 'idx_study_cards_language_due'",
        )
        .get();
    expect(indexes, hasLength(1));
  });

  test('duplicate headwords abort the migration and keep schema 5', () async {
    final file = await v5File();
    createV5(file, duplicateWords: true);
    final database = AppDatabase(NativeDatabase(file));
    expect(database.customSelect('SELECT 1').get(), throwsA(anything));
    await database.close();
    final raw = sqlite3.open(file.path);
    final version = raw.select('PRAGMA user_version').single.values.single;
    final columns = raw.select('PRAGMA table_info(words)');
    raw.close();
    expect(version, 5);
    expect(columns.any((row) => row['name'] == 'language'), isFalse);
  });

  test('Korean and English counts, streaks and undo stay separate', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final now = DateTime(2026, 11, 16, 9);
    final korean = await database.addManualWord(
      const WordDraft(korean: '하늘', meaningZh: '天', partOfSpeech: '名词'),
    );
    final english = await database.addManualWord(
      const WordDraft(korean: 'sky', meaningZh: '天'),
      language: 'en',
    );
    await database.persistReview(
      wordId: korean,
      submissionToken: 'ko-1',
      rating: 3,
      reviewedAt: now.toUtc(),
      localDay: now,
      durationMs: 1000,
      cardMap: {'state': 2, 'due': now.toUtc().toIso8601String()},
      reviewLogMap: {},
    );
    await database.persistReview(
      wordId: english,
      submissionToken: 'en-1',
      rating: 1,
      reviewedAt: now.toUtc(),
      localDay: now,
      durationMs: 1000,
      cardMap: {'state': 2, 'due': now.toUtc().toIso8601String()},
      reviewLogMap: {},
    );
    await database.saveDailyPlanSettings(
      const DailyPlanSettings(newWordsPerDay: 8, reviewsPerDay: 40),
      'en',
    );

    expect((await database.loadHomeCounts(now.toUtc(), 'ko')).newWords, 0);
    expect((await database.loadHomeCounts(now.toUtc(), 'en')).completed, 1);
    expect((await database.loadDailyPlanProgress(now, 'ko')).newWordsDone, 1);
    expect((await database.loadDailyPlanProgress(now, 'ko')).reviewsDone, 0);
    expect((await database.loadDailyPlanProgress(now, 'en')).newWordsDone, 1);
    expect((await database.loadDailyPlanProgress(now, 'en')).reviewsDone, 0);
    expect((await database.loadDailyPlanSettings('en')).newWordsPerDay, 8);
    expect((await database.loadDailyPlanSettings('ko')).newWordsPerDay, 20);
    expect((await database.loadCheckins(now, 'ko')).streak, 1);
    expect((await database.loadCheckins(now, 'en')).streak, 1);
    expect((await database.undoLastReview(now, 'en'))?.id, english);
    expect((await database.loadCheckins(now, 'ko')).streak, 1);
    expect(await database.cardForWord(korean), isNotNull);
    expect(await database.cardForWord(english), isNull);
  });

  test('a version 1 backup restores as Korean', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.addManualWord(
      const WordDraft(korean: '하늘', meaningZh: '天', partOfSpeech: '名词'),
      language: 'en',
    );
    await database.addManualWord(
      const WordDraft(korean: '바다', meaningZh: '海', partOfSpeech: '名词'),
    );
    final snapshot = await database.createBackupSnapshot();
    expect(snapshot['version'], 2);
    final words = (snapshot['tables'] as Map)['words'] as List;
    expect(words, hasLength(2));
    expect(words.any((row) => row['language'] == 'en'), isTrue);
    expect(words.every((row) => row.containsKey('ipa')), isTrue);

    final restored = AppDatabase(NativeDatabase.memory());
    addTearDown(restored.close);
    await restored.restoreBackupSnapshot(snapshot);
    final rows = await restored.select(restored.words).get();
    expect(rows.map((row) => row.korean).toSet(), {'하늘', '바다'});

    final legacy = {
      'format': 'korean-memo-backup',
      'version': 1,
      'tables': {
        'words': [
          {
            'id': 1,
            'korean': '바다',
            'normalized_korean': '바다',
            'base_form': '',
            'normalized_base_form': '',
            'meaning_zh': '海',
            'pronunciation': null,
            'part_of_speech': '名词',
            'example_ko': null,
            'example_zh': null,
            'topik_level': null,
            'category': null,
            'tags': null,
            'note': null,
            'hanja': null,
            'etymology': null,
            'source': null,
            'created_at': 1,
            'updated_at': 1,
          },
        ],
        'word_books': <Map<String, Object?>>[],
        'word_book_words': <Map<String, Object?>>[],
        'study_cards': <Map<String, Object?>>[],
        'review_logs': <Map<String, Object?>>[],
        'user_words': <Map<String, Object?>>[],
        'daily_statistics': <Map<String, Object?>>[],
        'app_settings': [
          {'key': 'checkin:2026-11-01', 'value': '1', 'updated_at': 1},
        ],
      },
    };
    final fromV1 = AppDatabase(NativeDatabase.memory());
    addTearDown(fromV1.close);
    await fromV1.addManualWord(
      const WordDraft(korean: 'sky', meaningZh: '天'),
      language: 'en',
    );
    await fromV1.restoreBackupSnapshot(legacy);
    final koreanOnly = await fromV1.select(fromV1.words).get();
    expect(koreanOnly, hasLength(1));
    expect(koreanOnly.single.korean, '바다');
    expect(koreanOnly.single.language, 'ko');
    expect(koreanOnly.single.ipa, isNull);
  });

  test('restoring English keeps Korean words and check-ins', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.addManualWord(
      const WordDraft(korean: '바다', meaningZh: '海', partOfSpeech: '名词'),
    );
    await database.saveSetting('checkin:ko:2026-11-01', '1');
    await database.addManualWord(
      const WordDraft(korean: 'old', meaningZh: '旧'),
      language: 'en',
    );
    final snapshot = await database.createBackupSnapshot();
    await database.addManualWord(
      const WordDraft(korean: 'sky', meaningZh: '天', ipa: 'skaɪ'),
      language: 'en',
    );
    await database.restoreBackupSnapshot(snapshot, onlyLanguage: 'en');
    final rows = await database.select(database.words).get();
    expect(rows.map((row) => '${row.language}:${row.korean}').toSet(), {
      'ko:바다',
      'en:old',
    });
    expect(await database.loadSetting('checkin:ko:2026-11-01'), '1');
  });
}

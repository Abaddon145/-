import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/core/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  Future<File> databaseFile() async {
    final directory = await Directory.systemTemp.createTemp('koreanmemo-head');
    addTearDown(() => directory.delete(recursive: true));
    return File('${directory.path}/memo.sqlite');
  }

  void createLegacyWords(File target, {required int version}) {
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
        ipa TEXT,
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
        language TEXT NOT NULL DEFAULT 'ko',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    raw.execute(
      "INSERT INTO words (korean, normalized_korean, meaning_zh, ipa, language, created_at, updated_at) VALUES ('sky', 'sky', '天空', 'skaɪ', 'en', 1, 1)",
    );
    raw.execute(
      'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at INTEGER NOT NULL)',
    );
    raw.execute('PRAGMA user_version = $version');
    raw.close();
  }

  Future<void> expectHeadword(AppDatabase database) async {
    final columns = await database
        .customSelect('PRAGMA table_info(words)')
        .get();
    final names = columns.map((row) => row.read<String>('name')).toSet();
    expect(names.contains('headword'), isTrue);
    expect(names.contains('korean'), isFalse);
    final word = await database.select(database.words).getSingle();
    expect(word.headword, 'sky');
    expect(word.meaningZh, '天空');
    expect(word.ipa, 'skaɪ');
    expect(word.language, 'en');
    final version = await database
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(version.read<int>('user_version'), 9);
  }

  test('a fresh database stores the headword column', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.addManualWord(
      const WordDraft(korean: '바다', meaningZh: '海', partOfSpeech: '名词'),
    );
    final columns = await database
        .customSelect('PRAGMA table_info(words)')
        .get();
    final names = columns.map((row) => row.read<String>('name')).toSet();
    expect(names.contains('headword'), isTrue);
    expect(names.contains('korean'), isFalse);
    expect((await database.select(database.words).getSingle()).headword, '바다');
  });

  test('schema 7 upgrades korean into headword', () async {
    final file = await databaseFile();
    createLegacyWords(file, version: 7);
    final database = AppDatabase(NativeDatabase(file));
    addTearDown(database.close);
    await expectHeadword(database);
  });

  test('a version 8 database that still has korean is repaired', () async {
    final file = await databaseFile();
    createLegacyWords(file, version: 8);
    final database = AppDatabase(NativeDatabase(file));
    addTearDown(database.close);
    await expectHeadword(database);
  });

  test('a version 2 backup that still says korean restores', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final modern = await database.createBackupSnapshot();
    final words = (modern['tables'] as Map)['words'] as List;
    if (words.isNotEmpty) {
      expect(words.first.containsKey('headword'), isTrue);
      expect(words.first.containsKey('korean'), isFalse);
    }
    final legacy = {
      'format': 'korean-memo-backup',
      'version': 2,
      'tables': {
        'words': [
          {
            'id': 3,
            'korean': 'book',
            'normalized_korean': 'book',
            'base_form': '',
            'normalized_base_form': '',
            'meaning_zh': '书',
            'pronunciation': null,
            'part_of_speech': null,
            'example_ko': null,
            'example_zh': null,
            'topik_level': null,
            'category': null,
            'tags': null,
            'note': null,
            'hanja': null,
            'etymology': null,
            'source': null,
            'language': 'en',
            'ipa': 'bʊk',
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
        'app_settings': <Map<String, Object?>>[],
      },
    };
    await database.restoreBackupSnapshot(legacy);
    final restored = await database.select(database.words).getSingle();
    expect(restored.headword, 'book');
    expect(restored.language, 'en');
    expect(restored.ipa, 'bʊk');
  });
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/core/database/app_database.dart';
import 'package:korean_memo/features/atlas/data/atlas_media_cache.dart';
import 'package:korean_memo/features/atlas/domain/atlas_fill.dart';
import 'package:korean_memo/features/atlas/domain/atlas_models.dart';
import 'package:korean_memo/features/atlas/domain/atlas_quiz.dart';
import 'package:korean_memo/features/atlas/domain/ui_sounds.dart';
import 'package:korean_memo/features/typing/domain/typing_meter.dart';
import 'package:korean_memo/services/fsrs_service.dart';

void main() {
  test('schema 8 gains atlas columns without touching Korean rows', () async {
    final directory = await Directory.systemTemp.createTemp('atlas-schema');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/memo.sqlite');
    final created = AppDatabase(NativeDatabase(file));
    final id = await created.addManualWord(
      const WordDraft(korean: '학교', meaningZh: '学校', partOfSpeech: '名词'),
    );
    await created.customStatement(
      'DROP INDEX IF EXISTS idx_word_books_stable_id',
    );
    await created.customStatement('DROP TABLE atlas_entries');
    await created.customStatement(
      'ALTER TABLE word_books DROP COLUMN stable_id',
    );
    await created.customStatement('PRAGMA user_version = 8');
    await created.close();

    final upgraded = AppDatabase(NativeDatabase(file));
    addTearDown(upgraded.close);
    final tables = await upgraded
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'atlas_entries'",
        )
        .get();
    expect(tables, hasLength(1));
    final columns = await upgraded
        .customSelect('PRAGMA table_info(word_books)')
        .get();
    expect(
      columns.map((row) => row.read<String>('name')),
      contains('stable_id'),
    );
    final word = await (upgraded.select(
      upgraded.words,
    )..where((row) => row.id.equals(id))).getSingle();
    expect(word.headword, '학교');
    expect(word.language, 'ko');
  });

  test(
    'version 2 backups restore and atlas text round-trips without media',
    () async {
      final source = AppDatabase(NativeDatabase.memory());
      final restored = AppDatabase(NativeDatabase.memory());
      addTearDown(source.close);
      addTearDown(restored.close);
      await source.importAtlasEntries([_library()]);
      final cardBefore = await source.cardForWord(
        (await source.select(source.words).get()).single.id,
      );
      expect(cardBefore, isNull);
      final snapshot = await source.createBackupSnapshot();
      final encoded = jsonEncode(snapshot);
      expect(encoded.contains('.webp'), isFalse);
      expect(encoded.contains('.mp3'), isFalse);
      expect(snapshot['version'], 3);

      final legacy = jsonDecode(encoded) as Map<String, dynamic>;
      legacy['version'] = 2;
      final tables = legacy['tables'] as Map<String, dynamic>;
      tables.remove('atlas_entries');
      for (final row in tables['word_books'] as List) {
        (row as Map<String, dynamic>).remove('stable_id');
      }
      for (final row in tables['daily_statistics'] as List) {
        final day = row as Map<String, dynamic>;
        day.remove('first_correct_count');
        day.remove('first_attempt_count');
      }
      await restored.restoreBackupSnapshot(legacy);
      expect(await restored.select(restored.words).get(), isNotEmpty);
      expect(
        await restored.atlasForWord(
          (await restored.select(restored.words).get()).single.id,
        ),
        isNull,
      );

      final again = AppDatabase(NativeDatabase.memory());
      addTearDown(again.close);
      await again.restoreBackupSnapshot(snapshot);
      final atlas = await again.atlasForWord(
        (await again.select(again.words).get()).single.id,
      );
      expect(atlas?.atlasId, 'library');
      expect(atlas?.senses, isNotEmpty);
    },
  );

  test('merging the same headword keeps FSRS and edited fields', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final book = await database.createWordBook(
      name: 'CET-4',
      sourceFileName: 'cet4',
      language: 'en',
    );
    await database.importWords(
      wordBookId: book,
      source: 'cet4',
      language: 'en',
      drafts: const [WordDraft(korean: 'library', meaningZh: '我的释义')],
    );
    final word = (await database.select(database.words).get()).single;
    final now = DateTime.utc(2026, 1, 2);
    await database.persistReview(
      wordId: word.id,
      submissionToken: 'keep',
      rating: 3,
      reviewedAt: now,
      localDay: now,
      durationMs: 1000,
      cardMap: {
        'state': 2,
        'due': now.add(const Duration(days: 4)).toIso8601String(),
        'stability': 4,
        'difficulty': 5,
        'reps': 1,
        'lapses': 0,
      },
      reviewLogMap: const {},
    );
    await database.importAtlasEntries([_library()]);
    final after = (await database.select(database.words).get()).single;
    final card = await database.cardForWord(after.id);
    expect(after.meaningZh, '我的释义');
    expect(after.ipa, isNotNull);
    expect(card?.stability, 4);
    expect(card?.reps, 1);
    final atlas = await database.atlasForWord(after.id);
    expect(atlas?.examples, hasLength(2));
    expect((await database.select(database.wordBooks).get()).length, 2);
    await database.importAtlasEntries([_library(meaning: '不该覆盖')]);
    expect(
      (await database.select(database.words).get()).single.meaningZh,
      '我的释义',
    );
    expect(await database.select(database.studyCards).get(), hasLength(1));
  });

  test('only the first answer scores and a hint cannot exceed Hard', () {
    final words = [
      _quiz('abandon', '放弃', 'v.', 'B1'),
      _quiz('abundant', '丰富的', 'adj.', 'B2'),
      _quiz('ability', '能力', 'n.', 'B1'),
    ];
    final session = AtlasSession(
      steps: buildAtlasJourney(
        reviews: [words.first],
        fresh: words.skip(1).toList(),
      ),
    );
    expect(session.steps.first.phase, AtlasStepKind.recall);
    expect(session.writesScore(session.current!), isTrue);
    session.answer(correct: false, hasImage: false);
    expect(session.scoredIds, {words.first.id});
    final retry = session.steps.where(
      (step) => step.wordId == words.first.id && step.retry > 0,
    );
    expect(retry, isNotEmpty);
    expect(retry.first.scored, isFalse);
    expect(session.writesScore(retry.first), isFalse);
    expect(
      gradeAtlasAnswer(
        correct: true,
        elapsed: const Duration(seconds: 2),
        usedHint: true,
        kind: AtlasQuestionKind.spelling,
      ),
      StudyRating.hard,
    );
    expect(
      capRatingForHint(StudyRating.easy, usedHint: true),
      StudyRating.hard,
    );
    expect(
      gradeAtlasAnswer(
        correct: true,
        elapsed: const Duration(seconds: 3),
        usedHint: false,
        kind: AtlasQuestionKind.spelling,
      ),
      StudyRating.easy,
    );
    final question = buildAtlasQuestion(
      word: words[1],
      kind: AtlasQuestionKind.meaning,
      pool: words,
    );
    expect(question.options, contains('丰富的'));
    expect(question.options.length, greaterThan(1));
  });

  test('typing speed counts five correct characters as one word', () {
    final meter = TypingMeter();
    meter.commit(typed: 'abcde', expected: 'abcde', elapsedMs: 60000);
    expect(meter.wpm, 1);
    expect(meter.accuracy, 1);
    meter.commit(typed: 'axcde', expected: 'abcde', elapsedMs: 60000);
    expect(meter.correctChars, 9);
    expect(meter.wpm, closeTo(0.9, 0.001));
  });

  test('media cache evicts past the cap and clears', () async {
    final cache = AtlasMediaCache(
      store: MemoryByteStore(),
      maxBytes: 10,
      fetcher: (uri) async => Uint8List(4),
    );
    await cache.get(Uri.parse('https://example.test/a'));
    await cache.get(Uri.parse('https://example.test/b'));
    await cache.get(Uri.parse('https://example.test/c'));
    expect(await cache.sizeBytes(), lessThanOrEqualTo(10));
    final failed = AtlasMediaCache(
      store: MemoryByteStore(),
      fetcher: (_) async => null,
    );
    expect(await failed.get(Uri.parse('https://example.test/nope')), isNull);
    await cache.clear();
    expect(await cache.sizeBytes(), 0);
    expect(uiSoundWav(UiSoundKind.correct).length, greaterThan(44));
    expect(shouldPlayUiSound(enabled: true, reduceMotion: true), isFalse);
  });

  test('atlas fill keeps occupied fields', () {
    final draft = parseAtlasFill(
      jsonEncode({
        'senses': [
          {'pos': 'n.', 'zh': '图书馆', 'en': 'A library.'},
        ],
        'examples': [
          {'en': 'I went to the library.', 'zh': '我去了图书馆。'},
          {'en': 'Libraries support study.', 'zh': '图书馆支持学习。'},
        ],
        'collocations': ['public library｜公共图书馆'],
        'family': ['librarian (n.)'],
        'tip': '不是书店',
        'cefr': 'A1',
        'topic': 'education',
      }),
      headword: 'library',
    );
    expect(draft?.examples, hasLength(2));
    expect(draft?.cefr, 'A1');
    final occupied = AtlasRecord(
      wordId: 1,
      atlasId: 'library',
      ipaUk: '',
      ipaUs: '',
      senses: const [AtlasSense(pos: 'n.', zh: '已有', en: '')],
      examples: const [],
      collocations: const [],
      family: const [],
      synonyms: const [],
      antonyms: const [],
      tip: '',
      cefr: '',
      topic: '',
      mediaFlags: 0,
      usageNote: '',
    );
    expect(fillableAtlasFields(occupied), isNot(contains('senses')));
    expect(fillableAtlasFields(occupied), contains('examples'));
    expect(estimateStudyMinutes(reviews: 5, newWords: 5), greaterThan(0));
  });
}

AtlasEntryDraft _library({String meaning = '图书馆'}) => AtlasEntryDraft(
  id: 'library',
  word: 'library',
  ipaUk: '/ˈlaɪbrəri/',
  ipaUs: '/ˈlaɪbreri/',
  senses: [AtlasSense(pos: 'n.', zh: meaning, en: 'A place for books.')],
  examples: const [
    AtlasExample(en: 'I borrowed a book.', zh: '我借了一本书。'),
    AtlasExample(en: 'Libraries support learning.', zh: '图书馆支持学习。'),
  ],
  collocations: const ['public library｜公共图书馆'],
  family: const ['librarian (n.)'],
  synonyms: const [],
  antonyms: const [],
  tip: '不是书店',
  cefr: 'A1',
  topic: 'education',
  mediaFlags: 31,
  usageNote: '',
);

AtlasQuizWord _quiz(String word, String meaning, String pos, String cefr) =>
    AtlasQuizWord(
      id: word.hashCode,
      headword: word,
      meaning: meaning,
      pos: pos,
      cefr: cefr,
      hasImage: false,
      example: 'This is $word.',
    );

import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:korean_memo/core/database/app_database.dart';
import 'package:korean_memo/core/database/missing_meaning.dart';
import 'package:korean_memo/features/ai/data/ai_repository.dart';
import 'package:korean_memo/features/ai/domain/ai_models.dart';
import 'fixtures.dart';

void main() {
  late AppDatabase db;
  late AiRepository repo;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = AiRepository(db);
  });
  tearDown(() => db.close());
  AiRequest request(Word w) => AiRequest(
    requestId: const Uuid().v4(),
    word: w,
    context: '工厂设备',
    type: 'complete',
  );
  Future<AiSuggestion> generated(
    Word w, {
    Map<String, dynamic> changes = const {},
  }) async {
    final r = request(w), suggestion = suggestionFor(request(w));
    final output = suggestionFor(r, changes: changes);
    expect(suggestion.model, 'unit-test-model');
    await repo.store(r, output);
    return output;
  }

  test(
    'acceptance: missing English/Korean industrial term is edited and accepted without altering learning',
    () async {
      final word = await addAiWord(db, 'pressure / 압력', meaning: '原表未提供中文释义');
      final r = request(word);
      final preview = suggestionFor(
        r,
        changes: {
          'meaningZh': '压力；压强（具体依设备语境）',
          'terminologyNote': 'pressure 对应 압력，需确认设备与单位。',
        },
      );
      await repo.store(r, preview);
      expect((await repo.word(word.id))!.meaningZh, '原表未提供中文释义');
      await repo.save(
        preview.requestId,
        preview.edited({'meaningZh': '压力（设备工作语境）'}),
        {'meaningZh'},
      );
      expect((await repo.word(word.id))!.meaningZh, '压力（设备工作语境）');
      expect((await repo.word(word.id))!.source, word.source);
      expect(await db.cardForWord(word.id), isNull);
      expect(await db.select(db.reviewLogs).get(), isEmpty);
      expect((await db.loadCheckins(DateTime.now())).days, isEmpty);
    },
  );
  test(
    'malformed AI backup is rejected before deleting the current data',
    () async {
      final word = await addAiWord(db, '시험');
      await generated(word);
      final backup =
          jsonDecode(jsonEncode(await db.createBackupSnapshot(includeAi: true)))
              as Map<String, dynamic>;
      (((backup['tables'] as Map)['ai_suggestions'] as List).single
              as Map)['payload'] =
          '{';
      await expectLater(
        db.restoreBackupSnapshot(backup),
        throwsA(isA<FormatException>()),
      );
      expect((await repo.word(word.id))!.korean, word.korean);
      expect(await db.select(db.aiSuggestions).get(), hasLength(1));
    },
  );

  test(
    'one missing meaning predicate and library filter handle all supported placeholders',
    () async {
      for (final text in [
        null,
        '',
        '  ',
        '（待补中文）',
        '(待补中文)',
        '无中文',
        '暂无释义',
        'N/A',
        '原表未提供中文释义',
      ]) {
        expect(isMissingMeaning(text), true);
      }
      expect(isMissingMeaning('待补中文的词条'), false);
      expect(isMissingMeaning('学校'), false);
      await addAiWord(db, '시험');
      await addAiWord(db, '학교', meaning: '学校');
      final missing = await db.searchLibraryWords(
        query: '',
        filter: LibraryFilter.missingMeaning,
      );
      expect(missing.map((r) => r.word.korean), ['시험']);
    },
  );
  test(
    'valid schema and limits reject missing fields, invalid types, arrays and identity',
    () async {
      final word = await addAiWord(db, '시험'),
          r = request(word),
          valid = suggestionFor(request(word));
      expect(
        AiSuggestion.fromJson(valid.toJson().cast<String, dynamic>()).wordId,
        word.id,
      );
      for (final change in [
        <String, dynamic>{'meaningZh': null},
        {'wordId': '1'},
        {'collocations': List.filled(7, 'a')},
        {'meaningZh': List.filled(2001, 'a').join()},
        {'suspectedTypo': 'true'},
      ]) {
        expect(
          () => suggestionFor(r, changes: change),
          throwsA(isA<AiException>()),
        );
      }
      final missing = valid.toJson().cast<String, dynamic>();
      (missing['result'] as Map).remove('grammarNote');
      expect(() => AiSuggestion.fromJson(missing), throwsA(isA<AiException>()));
    },
  );
  test(
    'requestId and wordId mismatch are rejected at storage boundary',
    () async {
      final word = await addAiWord(db, '시험'), r = request(word);
      for (final change in [
        {'requestId': const Uuid().v4()},
        {'wordId': word.id + 1},
        {'originalTerm': 'wrong'},
      ]) {
        await expectLater(
          repo.store(r, suggestionFor(r, changes: change)),
          throwsA(isA<AiException>()),
        );
      }
      expect(await db.select(db.aiSuggestions).get(), isEmpty);
    },
  );
  test(
    'only checked fields save; source, notes, FSRS, counters, statistics and checkins stay intact',
    () async {
      final word = await addAiWord(db, '시험');
      await db.setFavorite(word.id, true);
      final now = DateTime.now();
      await db.persistReview(
        wordId: word.id,
        submissionToken: 'ai-regression-review',
        rating: 1,
        reviewedAt: now.toUtc(),
        localDay: now,
        durationMs: 2300,
        cardMap: {
          'state': 1,
          'due': now.toUtc().add(const Duration(days: 1)).toIso8601String(),
          'stability': 3.0,
          'difficulty': 4.0,
          'reps': 1,
          'lapses': 1,
          'last_review': now.toUtc().toIso8601String(),
        },
        reviewLogMap: {},
      );
      final before = await db.createBackupSnapshot();
      final suggestion = await generated((await repo.word(word.id))!);
      await repo.save(
        suggestion.requestId,
        suggestion.edited({'meaningZh': '用户编辑的中文'}),
        {'meaningZh', 'collocations'},
      );
      final after = await db.createBackupSnapshot();
      final originalTables = before['tables'] as Map,
          currentTables = after['tables'] as Map;
      for (final key in originalTables.keys.where((k) => k != 'words')) {
        expect(currentTables[key], originalTables[key], reason: '$key changed');
      }
      final updated = (await repo.word(word.id))!;
      expect(updated.meaningZh, '用户编辑的中文');
      expect(updated.partOfSpeech, word.partOfSpeech);
      expect(updated.exampleKo, word.exampleKo);
      expect(updated.note, word.note);
      expect(updated.source, word.source);
      final contents = await repo.contents(updated);
      expect(contents.keys.toSet(), {'meaningZh', 'collocations'});
      expect(contents['collocations'], '测试搭配');
      await expectLater(
        repo.save(suggestion.requestId, suggestion, {'meaningZh'}),
        throwsA(isA<AiException>()),
      );
    },
  );
  test(
    'original edits require concrete reconfirmation and rechecking the snapshot',
    () async {
      final word = await addAiWord(db, '시험'),
          suggestion = await generated(word);
      await db.updateWord(
        wordId: word.id,
        korean: word.korean,
        meaningZh: '人工填写',
      );
      await expectLater(
        repo.save(suggestion.requestId, suggestion, {'meaningZh'}),
        throwsA(isA<AiConflict>()),
      );
      final current = (await repo.word(word.id))!;
      expect(current.meaningZh, '人工填写');
      await db.updateWord(
        wordId: word.id,
        korean: word.korean,
        meaningZh: '再次人工修改',
      );
      await expectLater(
        repo.save(suggestion.requestId, suggestion, {
          'meaningZh',
        }, expectedSnapshot: aiSnapshotJson(current)),
        throwsA(isA<AiConflict>()),
      );
      await repo.save(suggestion.requestId, suggestion, {
        'meaningZh',
      }, expectedSnapshot: aiSnapshotJson((await repo.word(word.id))!));
    },
  );
  test(
    'deleted words reject writes and regenerated identities cannot replace the saved request',
    () async {
      final word = await addAiWord(db, '시험'),
          suggestion = await generated(word);
      await expectLater(
        repo.save(suggestion.requestId, suggestionFor(request(word)), {
          'meaningZh',
        }),
        throwsA(isA<AiException>()),
      );
      await db.deleteWord(word.id);
      await expectLater(
        repo.save(suggestion.requestId, suggestion, {'meaningZh'}),
        throwsA(isA<AiException>()),
      );
      expect(await db.select(db.words).get(), isEmpty);
    },
  );
  test(
    'typo candidates preserve spelling; separately confirmed changes check duplicate term and base form',
    () async {
      final word = await addAiWord(db, 'acuum');
      await addAiWord(db, 'vacuum');
      final s = await generated(
        word,
        changes: {
          'suspectedTypo': true,
          'suggestedSpellings': ['vacuum'],
          'needsMoreContext': true,
        },
      );
      await expectLater(
        repo.save(s.requestId, s, {'meaningZh'}, spelling: 'vacuum'),
        throwsA(isA<AiException>()),
      );
      await expectLater(
        repo.save(
          s.requestId,
          s,
          {'meaningZh'},
          spelling: 'vacuum',
          spellingConfirmed: true,
        ),
        throwsA(isA<AiException>()),
      );
      expect((await repo.word(word.id))!.korean, 'acuum');
      await repo.save(s.requestId, s, {'ambiguityNotes'});
      expect((await repo.word(word.id))!.korean, 'acuum');
    },
  );
  test(
    'cache keys include content context task prompt style count and normalized timestamps',
    () async {
      final word = await addAiWord(db, '시험'),
          r = request(word),
          s = suggestionFor(request(word));
      final real = suggestionFor(r);
      await repo.store(r, real);
      expect((await repo.cached(r))!.requestId, real.requestId);
      final equivalent = word.copyWith(
        createdAt: word.createdAt.toUtc(),
        updatedAt: word.updatedAt.toUtc(),
      );
      expect(aiSnapshotJson(equivalent), aiSnapshotJson(word));
      expect(
        aiCacheKey(word, '日常', 'complete', 'default', 1),
        isNot(aiCacheKey(word, '日常', 'explain', 'default', 1)),
      );
      expect(s.promptVersion, aiPromptVersion);
      await db.updateWord(
        wordId: word.id,
        korean: word.korean,
        meaningZh: '编辑',
      );
      expect(await repo.cached(request((await repo.word(word.id))!)), isNull);
    },
  );
  test(
    'optional AI backups, legacy restore, credentials exclusion and recovery retain AI data',
    () async {
      final word = await addAiWord(db, '시험'),
          suggestion = await generated(word);
      await repo.save(suggestion.requestId, suggestion, {'usageNote'});
      await repo.createTask([word], '日常韩语');
      await db.saveSetting('ai_access_token', 'unit-test-secret');
      final legacy = await db.createBackupSnapshot(),
          modern = await db.createBackupSnapshot(includeAi: true);
      expect((legacy['tables'] as Map).containsKey('ai_tasks'), false);
      expect(jsonEncode(modern), isNot(contains('unit-test-secret')));
      await db.restoreBackupSnapshot(legacy);
      expect(await db.select(db.aiSuggestions).get(), isEmpty);
      expect(await db.recoverPreviousRestore(), true);
      expect(await db.select(db.aiSuggestions).get(), hasLength(1));
      expect(await db.select(db.aiTasks).get(), hasLength(1));
      final other = AppDatabase(NativeDatabase.memory());
      addTearDown(other.close);
      await other.restoreBackupSnapshot(modern);
      expect(await other.select(other.aiWordContents).get(), hasLength(1));
      expect(await other.loadSetting('ai_access_token'), isNull);
    },
  );
  test(
    'schema v3 incrementally migrates without changing existing learning rows',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'koreanmemo-ai-migration',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/v3.sqlite');
      final old = AppDatabase(NativeDatabase(file));
      final word = await addAiWord(old, '시험');
      await old.setFavorite(word.id, true);
      await old.saveDailyPlanSettings(
        const DailyPlanSettings(newWordsPerDay: 250, reviewsPerDay: 111),
      );
      final before = (await old.createBackupSnapshot())['tables'];
      for (final name in [
        'ai_task_items',
        'ai_tasks',
        'ai_suggestions',
        'ai_word_contents',
      ]) {
        await old.customStatement('DROP TABLE $name');
      }
      await old.customStatement('PRAGMA user_version=3');
      await old.close();
      final upgraded = AppDatabase(NativeDatabase(file));
      addTearDown(upgraded.close);
      expect((await upgraded.createBackupSnapshot())['tables'], before);
      expect(await upgraded.select(upgraded.aiSuggestions).get(), isEmpty);
      expect((await upgraded.loadDailyPlanSettings()).newWordsPerDay, 250);
    },
  );
}

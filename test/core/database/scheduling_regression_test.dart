import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/core/database/app_database.dart';
import 'package:korean_memo/core/text/cloze_target.dart';
import 'package:korean_memo/features/settings/domain/backup_file.dart';
import 'package:korean_memo/features/study/domain/practice.dart';
import 'package:korean_memo/services/fsrs_service.dart';

void main() {
  const draft = WordDraft(korean: '사랑', meaningZh: '爱', partOfSpeech: '名词');

  Future<AppDatabase> open() async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    return database;
  }

  Future<int> add(AppDatabase database, String korean, {String? example}) {
    return database.addManualWord(
      WordDraft(
        korean: korean,
        meaningZh: '释义',
        partOfSpeech: '名词',
        exampleKo: example,
      ),
    );
  }

  Future<void> card(
    AppDatabase database,
    int id, {
    required int state,
    required DateTime due,
    int lapses = 0,
  }) {
    return database
        .into(database.studyCards)
        .insert(
          StudyCardsCompanion.insert(
            wordId: id,
            state: Value(state),
            due: due,
            lapses: Value(lapses),
            fsrsJson: '{}',
            createdAt: due,
            updatedAt: due,
          ),
        );
  }

  test(
    'learning steps stay available and do not spend the review cap',
    () async {
      final database = await open();
      final now = DateTime(2026, 11, 9, 12);
      final learning = await add(database, '학습');
      final mature = await add(database, '복습');
      final fresh = await add(database, '새단어');
      await card(database, learning, state: 1, due: now.toUtc());
      await card(database, mature, state: 2, due: now.toUtc());
      await database.saveDailyPlanSettings(
        const DailyPlanSettings(newWordsPerDay: 20, reviewsPerDay: 100),
      );
      await database
          .into(database.dailyStatistics)
          .insert(
            DailyStatisticsCompanion.insert(
              date: DateTime.utc(2026, 11, 9),
              reviewWords: const Value(100),
            ),
          );

      expect(
        (await database.nextTrainingWord(const SessionOptions(), now))?.id,
        learning,
      );

      await database.persistReview(
        wordId: learning,
        submissionToken: 'step',
        rating: 3,
        reviewedAt: now.toUtc(),
        localDay: now,
        durationMs: 1000,
        cardMap: {
          'state': 1,
          'due': now.toUtc().add(const Duration(minutes: 10)).toIso8601String(),
        },
        reviewLogMap: {},
      );
      final progress = await database.loadDailyPlanProgress(now);
      expect(progress.reviewsDone, 100);
      expect(progress.newWordsDone, 0);
      await database.saveSetting('word_status:$learning', 'suspended');
      expect(
        (await database.nextTrainingWord(const SessionOptions(), now))?.id,
        fresh,
      );
      expect(
        (await database.nextTrainingWord(const SessionOptions(), now))?.id,
        isNot(mature),
      );
    },
  );

  test('mixed spelling never pulls a future-due card', () async {
    final database = await open();
    final now = DateTime(2026, 11, 9, 12);
    final future = await add(database, '미래');
    final fresh = await add(database, '현재');
    await card(
      database,
      future,
      state: 2,
      due: now.toUtc().add(const Duration(days: 4)),
    );
    const options = SessionOptions(
      daily: false,
      mode: PracticeMode.spelling,
      queue: QueueKind.mixed,
    );
    expect((await database.nextTrainingWord(options, now))?.id, fresh);
    await database.saveSetting('word_status:$fresh', 'known');
    expect(await database.nextTrainingWord(options, now), isNull);
  });

  test('another daily round uses nextTrainingWord', () async {
    final database = await open();
    final now = DateTime(2026, 11, 9, 12);
    final id = await add(database, '추가');
    await database.saveDailyPlanSettings(
      const DailyPlanSettings(newWordsPerDay: 20, reviewsPerDay: 100),
    );
    await database
        .into(database.dailyStatistics)
        .insert(
          DailyStatisticsCompanion.insert(
            date: DateTime.utc(2026, 11, 9),
            newWords: const Value(20),
          ),
        );
    expect(
      await database.nextTrainingWord(const SessionOptions(), now),
      isNull,
    );
    await database.startExtraStudyRound(now, 10);
    expect(
      (await database.nextTrainingWord(const SessionOptions(), now))?.id,
      id,
    );
  });

  test('Good intervals follow the learning step and then at least one day', () {
    final service = FsrsService();
    final at = DateTime.utc(2026, 11, 9, 8);
    final preview = service.preview(
      wordId: 1,
      storedCardJson: null,
      reviewDateTime: at,
      desiredRetention: 0.9,
    );
    final again = service.review(
      wordId: 1,
      storedCardJson: null,
      rating: StudyRating.again,
      reviewDateTime: at,
      desiredRetention: 0.9,
    );
    expect(preview[StudyRating.again]!.card['due'], again.card['due']);
    expect(preview[StudyRating.good]!.intervalLabel, '10 分钟');
    final firstDue = DateTime.parse(
      preview[StudyRating.good]!.card['due']! as String,
    );
    expect(firstDue.difference(at), const Duration(minutes: 10));
    final graduated = service.review(
      wordId: 1,
      storedCardJson: jsonEncode(preview[StudyRating.good]!.card),
      rating: StudyRating.good,
      reviewDateTime: firstDue,
      desiredRetention: 0.9,
    );
    expect(graduated.card['state'], 2);
    final span = DateTime.parse(
      graduated.card['due']! as String,
    ).difference(firstDue);
    expect(span.inDays, inInclusiveRange(1, 365));
  });

  test('eight review lapses suspend the card and undo restores it', () async {
    final database = await open();
    final now = DateTime(2026, 11, 9, 12);
    final id = await add(database, '어려움');
    await card(database, id, state: 2, due: now.toUtc(), lapses: 7);
    final result = await database.persistReview(
      wordId: id,
      submissionToken: 'leech',
      rating: 1,
      reviewedAt: now.toUtc(),
      localDay: now,
      durationMs: 500,
      cardMap: {
        'state': 3,
        'due': now.toUtc().add(const Duration(minutes: 10)).toIso8601String(),
      },
      reviewLogMap: {},
    );
    expect(result.leechSuspended, isTrue);
    expect(result.lapses, leechLapseThreshold);
    expect(await database.loadSetting('word_status:$id'), 'suspended');
    expect(
      await database.nextTrainingWord(const SessionOptions(), now),
      isNull,
    );
    expect((await database.undoLastReview(now))?.id, id);
    expect(await database.loadSetting('word_status:$id'), isNull);
    expect((await database.cardForWord(id))!.lapses, 7);
  });

  test('a study session and the library can use one word book', () async {
    final database = await open();
    final now = DateTime(2026, 11, 9, 12);
    final special = await database.createWordBook(
      name: '专项',
      sourceFileName: 'special',
    );
    final general = await database.createWordBook(
      name: '日常',
      sourceFileName: 'daily',
    );
    await database.importWords(
      wordBookId: special,
      source: 'special',
      drafts: const [draft],
    );
    await database.importWords(
      wordBookId: general,
      source: 'daily',
      drafts: const [
        WordDraft(korean: '학교', meaningZh: '学校', partOfSpeech: '名词'),
      ],
    );
    final options = SessionOptions(bookId: special);
    expect((await database.nextTrainingWord(options, now))?.korean, '사랑');
    expect(
      (await database.searchLibraryWords(
        query: '',
        filter: LibraryFilter.all,
        bookId: special,
      )).map((entry) => entry.word.korean),
      ['사랑'],
    );
  });

  test('cloze queue and the card use the same target', () async {
    final database = await open();
    final now = DateTime(2026, 11, 9, 12);
    await add(database, '사랑 / 학교', example: '학교에 가요');
    final kept = await add(database, 'love / 사랑', example: '나는 사랑을 해요');
    const options = SessionOptions(daily: false, mode: PracticeMode.cloze);
    final word = await database.nextTrainingWord(options, now);
    expect(word?.id, kept);
    final item = practiceItem(word!, options);
    expect(clozeTarget('사랑 / 학교'), '사랑');
    expect(clozeTarget('love / 사랑'), '사랑');
    expect(item.question.contains('＿＿＿'), isTrue);
    expect(item.answer, '사랑');
  });

  test(
    'restore without AI tables keeps AI rows and retention survives backup',
    () async {
      final database = await open();
      final restored = AppDatabase(NativeDatabase.memory());
      addTearDown(restored.close);
      final id = await add(database, '시험');
      await database
          .into(database.aiSuggestions)
          .insert(
            AiSuggestionsCompanion.insert(
              id: 'suggestion',
              wordId: id,
              originalSnapshot: '{}',
              cacheKey: 'cache',
              taskType: 'complete',
              context: '日常',
              payload: '{}',
              createdAt: DateTime.utc(2026, 11, 9),
            ),
          );
      await database.saveSetting(retentionSettingKey, '0.85');
      final legacy = await database.createBackupSnapshot();
      expect((legacy['tables'] as Map).containsKey('ai_suggestions'), isFalse);
      await database.restoreBackupSnapshot(legacy);
      expect(await database.select(database.aiSuggestions).get(), hasLength(1));
      await restored.restoreBackupSnapshot(legacy);
      expect(
        normalizeDesiredRetention(
          await restored.loadSetting(retentionSettingKey),
        ),
        0.85,
      );
    },
  );

  test('export refuses a file the app cannot restore', () {
    final snapshot = {'notes': List<String>.filled(6, 'ab')};
    final pretty = utf8
        .encode(const JsonEncoder.withIndent('  ').convert(snapshot))
        .length;
    final compact = utf8.encode(jsonEncode(snapshot)).length;
    expect(compact, lessThan(pretty));
    final encoded = encodeBackupFile(snapshot, maxBytes: pretty - 1);
    expect(encoded.length, compact);
    expect(utf8.decode(encoded).contains('\n'), isFalse);
    expect(
      () => encodeBackupFile(snapshot, maxBytes: compact - 1),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('无法恢复'),
        ),
      ),
    );
  });
}

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/core/database/app_database.dart';
import 'package:korean_memo/core/theme/app_theme.dart';
import 'package:korean_memo/core/time/review_format.dart';
import 'package:korean_memo/features/study/data/study_repository.dart';
import 'package:korean_memo/features/study/domain/empty_queue.dart';
import 'package:korean_memo/features/study/domain/practice.dart';
import 'package:korean_memo/features/study/domain/study_draft.dart';
import 'package:korean_memo/features/study/presentation/study_controller.dart';
import 'package:korean_memo/services/fsrs_service.dart';

void main() {
  final now = DateTime(2026, 11, 10, 12);

  test('empty queue distinguishes a finished plan from a mode with nothing to practice', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(
      await db.explainEmptyTrainingQueue(const SessionOptions(), now),
      EmptyQueueKind.libraryEmpty,
    );

    await db.addManualWord(const WordDraft(korean: '하늘', meaningZh: '天空', partOfSpeech: '名词'));
    expect(
      await db.explainEmptyTrainingQueue(
        const SessionOptions(daily: false, mode: PracticeMode.cloze, target: 10),
        now,
      ),
      EmptyQueueKind.modeNeedsContent,
    );
    expect(
      await db.explainEmptyTrainingQueue(
        const SessionOptions(daily: false, filter: LibraryFilter.favorites, target: 10),
        now,
      ),
      EmptyQueueKind.filteredEmpty,
    );
    expect(
      await db.explainEmptyTrainingQueue(
        const SessionOptions(daily: false, queue: QueueKind.reviews, target: 10),
        now,
      ),
      EmptyQueueKind.nothingLeft,
    );

    const round = SessionOptions(daily: false, target: 2);
    await db.startSession(round, now);
    await db.saveSetting(
      round.storageKey,
      jsonEncode({'day': dayKey(now), 'done': 2, 'target': 2, 'seen': <int>[]}),
    );
    expect(await db.explainEmptyTrainingQueue(round, now), EmptyQueueKind.roundComplete);

    await db.into(db.dailyStatistics).insert(
      DailyStatisticsCompanion.insert(
        date: DateTime.utc(now.year, now.month, now.day),
        newWords: const Value(20),
        reviewWords: const Value(100),
      ),
    );
    expect(await db.explainEmptyTrainingQueue(const SessionOptions(), now), EmptyQueueKind.dailyPlanDone);
  });

  test('empty queue copy tells the learner what to do next', () {
    expect(emptyQueueCopy(EmptyQueueKind.dailyPlanDone, const SessionOptions()).title, '今日计划已完成');
    expect(
      emptyQueueCopy(
        EmptyQueueKind.modeNeedsContent,
        const SessionOptions(mode: PracticeMode.cloze),
      ).body,
      contains('例句'),
    );
    expect(
      emptyQueueCopy(
        EmptyQueueKind.modeNeedsContent,
        const SessionOptions(mode: PracticeMode.forms),
      ).body,
      contains('活用表'),
    );
  });

  test('answer diff aligns shifted characters and does not change grading', () {
    expect(answerMatches('안녕 하세요', '안녕하세요'), isTrue);
    final same = diffAnswer('abc', 'abc');
    expect(same.expected.every((mark) => mark.match), isTrue);
    final shifted = diffAnswer('bc', 'abc');
    expect(shifted.expected.map((mark) => mark.match).toList(), [false, true, true]);
    final korean = diffAnswer('녕하세요', '안녕하세요');
    expect(korean.expected.first.match, isFalse);
    expect(korean.expected.skip(1).every((mark) => mark.match), isTrue);
    expect(answerMatches('녕하세요', '안녕하세요'), isFalse);
  });

  test('study draft round-trips and ignores broken payloads', () {
    const draft = StudyDraft(
      wordId: 3,
      sessionKey: 'daily',
      answer: '안녕',
      revealed: true,
      correct: false,
    );
    final decoded = StudyDraft.decode(draft.encode());
    expect(decoded?.wordId, 3);
    expect(decoded?.answer, '안녕');
    expect(decoded?.revealed, isTrue);
    expect(decoded?.correct, isFalse);
    expect(StudyDraft.decode(null), isNull);
    expect(StudyDraft.decode('not-json'), isNull);
  });

  test('review times use calendar words instead of a raw timestamp', () {
    final clock = DateTime(2026, 11, 10, 15, 4);
    expect(formatReviewMoment(DateTime(2026, 11, 10, 18, 30), now: clock), '今天 18:30');
    expect(formatReviewMoment(DateTime(2026, 11, 11, 8, 5), now: clock), '明天 08:05');
    expect(formatReviewMoment(DateTime(2025, 12, 1, 9, 0), now: clock), '2025年12月1日 09:00');
  });

  test('undo failure keeps the current card instead of becoming a load error', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.addManualWord(const WordDraft(korean: '하늘', meaningZh: '天空', partOfSpeech: '名词'));
    await db.saveSetting(
      'last_review_undo',
      jsonEncode({'day': '1999-01-01', 'token': 'stale', 'wordId': 1}),
    );
    final controller = StudyController(StudyRepository(db, FsrsService()));
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.state.word?.korean, '하늘');
    expect(controller.state.canUndo, isFalse);

    final message = await controller.undo();
    expect(message, '只能撤销今天最近的一次评分');
    expect(controller.state.error, isNull);
    expect(controller.state.word?.korean, '하늘');
  });

  test('a missing undo record explains itself and leaves the queue in place', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.addManualWord(const WordDraft(korean: '하늘', meaningZh: '天空', partOfSpeech: '名词'));
    final controller = StudyController(StudyRepository(db, FsrsService()));
    addTearDown(controller.dispose);
    await controller.load();
    final message = await controller.undo();
    expect(message, '没有可以撤销的评分');
    expect(controller.state.error, isNull);
    expect(controller.state.isComplete, isFalse);
    expect(controller.state.word?.korean, '하늘');
  });

  test('light presets can build a dark variant without replacing the night preset', () {
    final porcelain = AppTheme.preset('porcelain');
    expect(AppTheme.forPreset(porcelain).brightness, Brightness.light);
    expect(
      AppTheme.forPreset(porcelain, brightness: Brightness.dark).brightness,
      Brightness.dark,
    );
    expect(AppTheme.forPreset(AppTheme.preset('night')).brightness, Brightness.dark);
  });
}

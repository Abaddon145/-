import 'dart:async';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/core/database/app_database.dart';
import 'package:korean_memo/features/ai/data/ai_client.dart';
import 'package:korean_memo/features/ai/data/ai_repository.dart';
import 'package:korean_memo/features/ai/data/ai_task_runner.dart';
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
  Future<List<Word>> words(int count) async => [
    for (var i = 0; i < count; i++) await addAiWord(db, '시험$i'),
  ];
  test(
    'batch limit applies only to selected AI words, not study targets',
    () async {
      await expectLater(
        repo.createTask(await words(21), '日常韩语'),
        throwsA(isA<AiException>()),
      );
      expect(await db.select(db.aiTasks).get(), isEmpty);
      await db.saveDailyPlanSettings(
        const DailyPlanSettings(newWordsPerDay: 400, reviewsPerDay: 100),
      );
      expect((await db.loadDailyPlanSettings()).newWordsPerDay, 400);
    },
  );
  test(
    'two workers persist each success, keep partial failures and retry only unfinished',
    () async {
      final selected = await words(5), gateway = TestGateway(failOnce: {'시험1'});
      final task = await repo.createTask(selected, '工厂设备'),
          runner = AiTaskRunner(repo, () => gateway);
      await runner.start(task);
      expect(gateway.peak, 2);
      expect(gateway.requests, hasLength(5));
      var items = await repo.items(task);
      expect(items.where((r) => r.status == 'awaitingReview'), hasLength(4));
      expect(items.where((r) => r.status == 'failed'), hasLength(1));
      expect(await db.select(db.aiSuggestions).get(), hasLength(4));
      final storedIds = items
          .map((r) => r.suggestionId)
          .whereType<String>()
          .toSet();
      await runner.start(task);
      items = await repo.items(task);
      expect(gateway.requests, hasLength(6));
      expect(items.every((r) => r.status == 'awaitingReview'), true);
      expect(
        items.map((r) => r.suggestionId).toSet().containsAll(storedIds),
        true,
      );
    },
  );
  test(
    'cancel aborts active requests, stops queue and preserves completed suggestions',
    () async {
      final selected = await words(6), gateway = BlockingGateway();
      final task = await repo.createTask(selected, '物流与仓储'),
          runner = AiTaskRunner(repo, () => gateway);
      final pending = runner.start(task);
      await gateway.twoStarted.future;
      expect(() => runner.start(task), throwsA(isA<AiException>()));
      await runner.cancelAll();
      await pending;
      expect(gateway.calls, 2);
      expect(gateway.aborted, 2);
      expect(
        (await repo.items(task)).every((r) => r.status == 'cancelled'),
        true,
      );
      final retry = TestGateway(), restored = AiTaskRunner(repo, () => retry);
      await restored.start(task);
      expect(retry.requests, hasLength(6));
      expect(await db.select(db.aiSuggestions).get(), hasLength(6));
    },
  );
  test(
    'reopening pauses interrupted tasks and never auto-starts them',
    () async {
      final task = await repo.createTask(await words(3), '工厂设备');
      final items = await repo.items(task);
      await (db.update(db.aiTasks)..where((r) => r.id.equals(task))).write(
        const AiTasksCompanion(status: Value('running')),
      );
      await (db.update(db.aiTaskItems)
            ..where((r) => r.id.equals(items.first.id)))
          .write(const AiTaskItemsCompanion(status: Value('running')));
      final gateway = TestGateway(), runner = AiTaskRunner(repo, () => gateway);
      await runner.ready;
      expect(gateway.requests, isEmpty);
      expect((await db.select(db.aiTasks).get()).single.status, 'paused');
      expect((await repo.items(task)).every((r) => r.status == 'queued'), true);
      await runner.start(task);
      expect(gateway.requests, hasLength(3));
    },
  );
  test(
    'changed/deleted words become conflicts and real meanings are never auto-overwritten',
    () async {
      final selected = await words(3),
          task = await repo.createTask(selected, '工厂设备');
      await db.updateWord(
        wordId: selected[0].id,
        korean: selected[0].korean,
        meaningZh: '人工释义',
      );
      await db.deleteWord(selected[1].id);
      final gateway = TestGateway(), runner = AiTaskRunner(repo, () => gateway);
      await runner.start(task);
      final items = await repo.items(task);
      expect(items.where((r) => r.status == 'conflict'), hasLength(2));
      expect(gateway.requests, hasLength(1));
      expect((await repo.word(selected[0].id))!.meaningZh, '人工释义');
      await expectLater(
        runner.confirmItemSnapshot(
          items.firstWhere((r) => r.wordId == selected[0].id).id,
        ),
        throwsA(isA<AiException>()),
      );
    },
  );
  test(
    'suspected spellings are local suggestions until explicitly reviewed',
    () async {
      final word = await addAiWord(db, 'clrculation'),
          task = await repo.createTask([word], '工厂设备');
      final gateway = TestGateway(typo: true),
          runner = AiTaskRunner(repo, () => gateway);
      await runner.start(task);
      expect((await repo.word(word.id))!.korean, 'clrculation');
      expect((await repo.word(word.id))!.meaningZh, '（待补中文）');
      expect((await repo.items(task)).single.status, 'awaitingReview');
    },
  );
}

class TestGateway implements AiGateway {
  TestGateway({this.failOnce = const {}, this.typo = false});
  final Set<String> failOnce;
  final bool typo;
  final requests = <AiRequest>[];
  final failed = <String>{};
  int running = 0, peak = 0;
  @override
  Future<String> health() async => 'test';
  @override
  Future<AiSuggestion> generate(
    AiRequest r,
    AiCancellation cancellation,
  ) async {
    requests.add(r);
    running++;
    if (running > peak) peak = running;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      cancellation.check();
      if (failOnce.contains(r.word.korean) && failed.add(r.word.korean)) {
        throw const AiException('provider_error');
      }
      return suggestionFor(
        r,
        changes: typo
            ? {
                'suspectedTypo': true,
                'suggestedSpellings': ['circulation'],
                'needsMoreContext': true,
              }
            : {},
      );
    } finally {
      running--;
    }
  }
}

class BlockingGateway implements AiGateway {
  int calls = 0, aborted = 0;
  final twoStarted = Completer<void>();
  @override
  Future<String> health() async => 'test';
  @override
  Future<AiSuggestion> generate(AiRequest r, AiCancellation cancel) async {
    if (++calls == 2) twoStarted.complete();
    await cancel.signal;
    aborted++;
    throw const AiException('cancelled');
  }
}

import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:korean_memo/core/database/app_database.dart';
import 'package:korean_memo/features/ai/data/ai_client.dart';
import 'package:korean_memo/features/ai/data/ai_repository.dart';
import 'package:korean_memo/features/ai/data/ai_task_runner.dart';
import 'package:korean_memo/features/ai/domain/ai_models.dart';
import 'package:korean_memo/features/settings/domain/backup_status.dart';
import 'package:korean_memo/features/study/domain/practice.dart';
import '../ai/fixtures.dart';

class BatchHttp extends http.BaseClient {
  BatchHttp(this.words, this.hangId);
  final Map<int, Word> words;
  final int hangId;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final data = jsonDecode((request as http.Request).body) as Map;
    if (data['wordId'] == hangId) {
      await (request as http.AbortableRequest).abortTrigger;
      throw http.RequestAbortedException(request.url);
    }
    final input = AiRequest(
      requestId: data['requestId'],
      word: words[data['wordId']]!,
      context: data['context'],
      type: 'complete',
    );
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(suggestionFor(input).toJson()))),
      200,
    );
  }

  @override
  void close() {}
}

void main() {
  test(
    'single HTTP timeout preserves other batch successes and timeout reason',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final words = [for (var i = 0; i < 3; i++) await addAiWord(db, '시험$i')];
      final repo = AiRepository(db);
      final id = await repo.createTask(words, '日常韩语');
      final client = AiProxyClient(
        address: 'https://mock.invalid',
        credential: 'test',
        timeout: const Duration(milliseconds: 150),
        clientFactory: () =>
            BatchHttp({for (final w in words) w.id: w}, words.first.id),
      );
      final runner = AiTaskRunner(repo, () => client);
      await runner.start(id);
      final items = await repo.items(id);
      expect(items.where((i) => i.status == 'awaitingReview'), hasLength(2));
      expect(
        items.singleWhere((i) => i.status == 'failed').errorCode,
        'timeout',
      );
      expect((await db.select(db.aiTasks).get()).single.status, 'paused');
    },
  );
  test(
    'backup export state stays on this device through old backup import and undo',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await addAiWord(db, '학교');
      await db.saveSetting('last_backup_at', '2026-10-25T01:00:00Z');
      await db.saveSetting('backup_snoozed_until', '2026-10-28T01:00:00Z');
      final backup = await db.createBackupSnapshot();
      final settings = (backup['tables'] as Map)['app_settings'] as List;
      expect(
        settings.where((r) => (r as Map)['key'] == 'last_backup_at'),
        isEmpty,
      );
      // Old backups may carry another device's export timestamp.
      settings.add({
        'key': 'last_backup_at',
        'value': '2020-01-01T00:00:00Z',
        'updated_at': 0,
      });
      await db.restoreBackupSnapshot(Map<String, dynamic>.from(backup));
      expect(await db.loadSetting('last_backup_at'), '2026-10-25T01:00:00Z');
      expect(
        await db.loadSetting('backup_snoozed_until'),
        '2026-10-28T01:00:00Z',
      );
      expect(await db.recoverPreviousRestore(), true);
      expect(await db.loadSetting('last_backup_at'), '2026-10-25T01:00:00Z');
      expect(await db.select(db.words).get(), hasLength(1));
    },
  );
  test('all shared missing-meaning placeholders use study fallback', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final word = await addAiWord(db, '학교');
    for (final text in ['（待补中文）', '待翻译', 'n/a', '—', '未提供中文释义']) {
      expect(
        practiceItem(
          word.copyWith(meaningZh: text),
          const SessionOptions(),
        ).answer,
        '暂无翻译，请在编辑中补充',
      );
    }
  });
  test('weekly reminders normalize instants and honor snooze and opt-out', () {
    final now = DateTime.parse('2026-10-25T08:00:00+08:00');
    expect(
      BackupStatus(
        lastExport: BackupStatus.parse('2026-10-18T00:00:00Z'),
      ).isDue(now),
      true,
    );
    expect(
      BackupStatus(
        lastExport: now.subtract(const Duration(days: 6)),
      ).isDue(now),
      false,
    );
    expect(
      BackupStatus(snoozedUntil: now.add(const Duration(hours: 1))).isDue(now),
      false,
    );
    expect(const BackupStatus(enabled: false).isDue(now), false);
    expect(BackupStatus.parse('bad'), isNull);
    expect(aiRetryAfterSeconds('9999'), 300);
    expect(aiRetryAfterSeconds('-1'), isNull);
  });
}

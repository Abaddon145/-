import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/core/database/app_database.dart';

void main() {
  test(
    'local-only upgrade removes cloud markers and preserves all learning tables',
    () async {
      final dir = await Directory.systemTemp.createTemp('korean-local-upgrade');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/existing.sqlite');
      var db = AppDatabase(NativeDatabase(file));
      final id = await db.addManualWord(
        const WordDraft(korean: '압력', meaningZh: '压力', partOfSpeech: '名词'),
      );
      final now = DateTime(2026, 10, 15, 12);
      await db.setFavorite(id, true);
      await db.saveDailyPlanSettings(
        const DailyPlanSettings(newWordsPerDay: 400, reviewsPerDay: 100),
      );
      await db.persistReview(
        wordId: id,
        submissionToken: 'upgrade-review',
        rating: 1,
        reviewedAt: now.toUtc(),
        localDay: now,
        durationMs: 2300,
        cardMap: {
          'state': 1,
          'due': now.toUtc().toIso8601String(),
          'stability': 3.0,
          'difficulty': 4.0,
        },
        reviewLogMap: {},
      );
      await db.saveSetting('cloud_binding', 'obsolete-device');
      final before = await db.createBackupSnapshot(includeAi: true);
      await db.close();
      db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      expect(await db.loadSetting('cloud_binding'), isNull);
      expect(
        (await db.createBackupSnapshot(includeAi: true))['tables'],
        before['tables'],
      );
      expect((await db.loadDailyPlanSettings()).newWordsPerDay, 400);
      expect(await db.select(db.reviewLogs).get(), hasLength(1));
    },
  );

  test(
    'legacy file with cloud settings restores locally and undo retains current data',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.addManualWord(
        const WordDraft(korean: '학교', meaningZh: '学校', partOfSpeech: '名词'),
      );
      final backup = await db.createBackupSnapshot();
      final tables = backup['tables'] as Map;
      (tables['app_settings'] as List).add({
        'key': 'cloud_binding',
        'value': 'old-account',
        'updated_at': DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
      });
      await db.addManualWord(
        const WordDraft(korean: '공장', meaningZh: '工厂', partOfSpeech: '名词'),
      );
      await db.restoreBackupSnapshot(backup.cast<String, dynamic>());
      expect(await db.loadSetting('cloud_binding'), isNull);
      expect(await db.select(db.words).get(), hasLength(1));
      expect(await db.recoverPreviousRestore(), true);
      expect(await db.select(db.words).get(), hasLength(2));
    },
  );
}

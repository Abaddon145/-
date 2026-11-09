part of 'app_database.dart';

extension BackupSnapshots on AppDatabase {
  Future<Map<String, Object?>> createBackupSnapshot({bool includeAi = false}) =>
      transaction(() async {
        final tables = [
          'words',
          'word_books',
          'word_book_words',
          'study_cards',
          'review_logs',
          'user_words',
          'daily_statistics',
          'app_settings',
          if (includeAi) ...[
            'ai_suggestions',
            'ai_tasks',
            'ai_task_items',
            'ai_word_contents',
          ],
        ];
        final data = <String, List<Map<String, Object?>>>{};
        const excludedSettings = {
          'ai_access_token',
          'ai_credential',
          'model_api_key',
          'last_backup_at',
          'backup_snoozed_until',
          'backup_reminders_enabled',
        };
        for (final table in tables) {
          final rows = await customSelect('SELECT * FROM $table').get();
          data[table] = [
            for (final row in rows)
              if (table != 'app_settings' ||
                  (!(row.data['key'] as String).startsWith('cloud_') &&
                      !excludedSettings.contains(row.data['key'])))
                Map<String, Object?>.from(row.data),
          ];
        }
        return {
          'format': 'korean-memo-backup',
          'version': 1,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'tables': data,
        };
      });

  Future<void> restoreBackupSnapshot(
    Map<String, dynamic> snapshot, {
    bool captureRecovery = true,
  }) async {
    final columns = <String, List<String>>{
      'words': [
        'id', 'korean', 'normalized_korean', 'base_form', 'normalized_base_form',
        'meaning_zh', 'pronunciation', 'part_of_speech', 'example_ko', 'example_zh',
        'topik_level', 'category', 'tags', 'note', 'hanja', 'etymology', 'source',
        'created_at', 'updated_at',
      ],
      'word_books': [
        'id', 'name', 'description', 'source_file_name', 'created_at', 'updated_at',
      ],
      'word_book_words': ['word_book_id', 'word_id', 'sort_order'],
      'study_cards': [
        'id', 'word_id', 'state', 'due', 'stability', 'difficulty', 'elapsed_days',
        'scheduled_days', 'reps', 'lapses', 'last_review', 'fsrs_json', 'created_at',
        'updated_at',
      ],
      'review_logs': [
        'id', 'word_id', 'submission_token', 'rating', 'reviewed_at', 'state_before',
        'state_after', 'elapsed_days', 'scheduled_days', 'duration_ms',
        'fsrs_review_log_json',
      ],
      'user_words': [
        'word_id', 'is_favorite', 'is_difficult', 'note', 'correct_count',
        'wrong_count', 'last_seen_at',
      ],
      'daily_statistics': [
        'date', 'new_words', 'review_words', 'correct_count', 'wrong_count',
        'study_duration_ms',
      ],
      'app_settings': ['key', 'value', 'updated_at'],
    };
    if (snapshot['format'] != 'korean-memo-backup' || snapshot['version'] != 1) {
      throw const FormatException('不支持的备份格式');
    }
    final payload = snapshot['tables'];
    if (payload is! Map) throw const FormatException('备份缺少数据');
    const aiColumns = <String, List<String>>{
      'ai_suggestions': [
        'id', 'word_id', 'original_snapshot', 'cache_key', 'task_type', 'context',
        'payload', 'saved_fields', 'created_at',
      ],
      'ai_tasks': ['id', 'context', 'status', 'created_at', 'updated_at'],
      'ai_task_items': [
        'id', 'task_id', 'word_id', 'original_snapshot', 'status', 'suggestion_id',
        'error_code', 'attempts',
      ],
      'ai_word_contents': [
        'word_id', 'field', 'value', 'request_id', 'model', 'prompt_version',
        'original_snapshot', 'generated_at', 'confirmed_at',
      ],
    };
    if (aiColumns.keys.any(payload.containsKey)) {
      if (!aiColumns.keys.every(payload.containsKey)) {
        throw const FormatException('AI 备份表不完整');
      }
      columns.addAll(aiColumns);
    }
    for (final entry in columns.entries) {
      final list = payload[entry.key];
      if (list is! List || list.length > maxBackupRowsPerTable) {
        throw FormatException('备份表无效：${entry.key}');
      }
      for (final row in list) {
        if (row is! Map ||
            row.keys.toSet().length != entry.value.length ||
            !entry.value.every(row.containsKey)) {
          throw FormatException('备份字段无效：${entry.key}');
        }
      }
    }
    if (columns.containsKey('ai_suggestions')) validateAiBackup(payload);
    await transaction(() async {
      final localBackupSettings = {
        for (final key in [
          'last_backup_at',
          'backup_snoozed_until',
          'backup_reminders_enabled',
        ])
          key: await loadSetting(key),
      };
      if (captureRecovery) {
        await into(recoverySnapshots).insertOnConflictUpdate(
          RecoverySnapshotsCompanion.insert(
            id: const Value(1),
            payload: jsonEncode(await createBackupSnapshot(includeAi: true)),
            createdAt: DateTime.now().toUtc(),
          ),
        );
      }
      final clearAi = columns.containsKey('ai_suggestions');
      for (final table in [
        if (clearAi) ...[
          'ai_word_contents',
          'ai_task_items',
          'ai_tasks',
          'ai_suggestions',
        ],
        'review_logs',
        'study_cards',
        'word_book_words',
        'user_words',
        'daily_statistics',
        'app_settings',
        'words',
        'word_books',
      ]) {
        await customStatement('DELETE FROM $table');
      }
      for (final table in columns.keys) {
        for (final raw in payload[table] as List) {
          final row = Map<String, Object?>.from(raw as Map);
          final names = columns[table]!;
          await customStatement(
            'INSERT INTO $table (${names.join(',')}) VALUES (${List.filled(names.length, '?').join(',')})',
            [for (final name in names) row[name]],
          );
        }
      }
      for (final entry in localBackupSettings.entries) {
        await saveSetting(entry.key, entry.value);
      }
      // An undo snapshot is valid only for the transaction that produced it on
      // this device; imported files must never provide executable row snapshots.
      await saveSetting('last_review_undo', null);
      await customStatement(
        "DELETE FROM app_settings WHERE substr(key,1,6) = 'cloud_'",
      );
      await customStatement(
        "DELETE FROM app_settings WHERE key IN ('ai_access_token','ai_credential','model_api_key')",
      );
      await customStatement(
        "UPDATE ai_tasks SET status = 'paused' WHERE status = 'running'",
      );
      await customStatement(
        "UPDATE ai_task_items SET status = 'queued' WHERE status = 'running'",
      );
    });
  }
}

part of 'app_database.dart';

const _backupLanguageTables = {
  'words',
  'word_books',
  'study_cards',
  'review_logs',
  'daily_statistics',
  'ai_suggestions',
  'ai_tasks',
  'ai_task_items',
  'ai_word_contents',
};

const _backupColumnsV1 = <String, List<String>>{
  'words': [
    'id',
    'korean',
    'normalized_korean',
    'base_form',
    'normalized_base_form',
    'meaning_zh',
    'pronunciation',
    'part_of_speech',
    'example_ko',
    'example_zh',
    'topik_level',
    'category',
    'tags',
    'note',
    'hanja',
    'etymology',
    'source',
    'created_at',
    'updated_at',
  ],
  'word_books': [
    'id',
    'name',
    'description',
    'source_file_name',
    'created_at',
    'updated_at',
  ],
  'word_book_words': ['word_book_id', 'word_id', 'sort_order'],
  'study_cards': [
    'id',
    'word_id',
    'state',
    'due',
    'stability',
    'difficulty',
    'elapsed_days',
    'scheduled_days',
    'reps',
    'lapses',
    'last_review',
    'fsrs_json',
    'created_at',
    'updated_at',
  ],
  'review_logs': [
    'id',
    'word_id',
    'submission_token',
    'rating',
    'reviewed_at',
    'state_before',
    'state_after',
    'elapsed_days',
    'scheduled_days',
    'duration_ms',
    'fsrs_review_log_json',
  ],
  'user_words': [
    'word_id',
    'is_favorite',
    'is_difficult',
    'note',
    'correct_count',
    'wrong_count',
    'last_seen_at',
  ],
  'daily_statistics': [
    'date',
    'new_words',
    'review_words',
    'correct_count',
    'wrong_count',
    'study_duration_ms',
  ],
  'app_settings': ['key', 'value', 'updated_at'],
};

const _aiColumnsV1 = <String, List<String>>{
  'ai_suggestions': [
    'id',
    'word_id',
    'original_snapshot',
    'cache_key',
    'task_type',
    'context',
    'payload',
    'saved_fields',
    'created_at',
  ],
  'ai_tasks': ['id', 'context', 'status', 'created_at', 'updated_at'],
  'ai_task_items': [
    'id',
    'task_id',
    'word_id',
    'original_snapshot',
    'status',
    'suggestion_id',
    'error_code',
    'attempts',
  ],
  'ai_word_contents': [
    'word_id',
    'field',
    'value',
    'request_id',
    'model',
    'prompt_version',
    'original_snapshot',
    'generated_at',
    'confirmed_at',
  ],
};

const _excludedBackupSettings = {
  'ai_access_token',
  'ai_credential',
  'model_api_key',
  'last_backup_at',
  'backup_snoozed_until',
  'backup_reminders_enabled',
};

List<String> _columnsFor(String table, int version) {
  final base = _backupColumnsV1[table] ?? _aiColumnsV1[table];
  if (base == null) return const [];
  if (version < 2 || !_backupLanguageTables.contains(table)) return base;
  final extra = table == 'words' ? ['language', 'ipa'] : ['language'];
  if (base.contains('created_at')) {
    final index = base.indexOf('created_at');
    return [...base.sublist(0, index), ...extra, ...base.sublist(index)];
  }
  return [...base, ...extra];
}

bool _keepBackupRow(String table, Map<String, Object?> row) {
  if (table != 'app_settings') return true;
  final key = row['key'] as String;
  return !key.startsWith('cloud_') && !_excludedBackupSettings.contains(key);
}

Map<String, Object?> _projectBackupRow(
  String table,
  Map<String, Object?> row,
  int version,
) {
  return {for (final name in _columnsFor(table, version)) name: row[name]};
}

String _legacySettingKey(String key) {
  if (key.startsWith('checkin:') &&
      !key.startsWith('checkin:ko:') &&
      !key.startsWith('checkin:en:')) {
    return 'checkin:ko:${key.substring(8)}';
  }
  if (key.startsWith('objective:') &&
      !key.startsWith('objective:ko:') &&
      !key.startsWith('objective:en:')) {
    return 'objective:ko:${key.substring(10)}';
  }
  const plain = {
    'daily_new_words',
    'daily_reviews',
    'study_round_day',
    'study_round_baseline',
    'study_round_target',
    'selected_learning_session',
    'fsrs_desired_retention',
    'auto_checkin',
    'speech_rate',
    'last_review_undo',
  };
  if ((plain.contains(key) || key.startsWith('learning_session:')) &&
      !key.startsWith('ko:') &&
      !key.startsWith('en:')) {
    return 'ko:$key';
  }
  return key;
}

String? _settingLanguage(String key) {
  if (key.startsWith('en:') ||
      key.startsWith('checkin:en:') ||
      key.startsWith('objective:en:')) {
    return 'en';
  }
  if (key.startsWith('ko:') ||
      key.startsWith('checkin:ko:') ||
      key.startsWith('objective:ko:')) {
    return 'ko';
  }
  return null;
}

final _wordSettingPattern = RegExp(
  r'^(word_status|word_forms|correct_streak):(\d+)$',
);
int _backupIdSerial = 0;

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
          if (includeAi) ..._aiColumnsV1.keys,
        ];
        final data = <String, List<Map<String, Object?>>>{};
        for (final table in tables) {
          final rows = await customSelect('SELECT * FROM $table').get();
          data[table] = [
            for (final row in rows)
              if (_keepBackupRow(table, row.data))
                _projectBackupRow(table, row.data, 2),
          ];
        }
        return {
          'format': 'korean-memo-backup',
          'version': 2,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'tables': data,
        };
      });

  Future<void> restoreBackupSnapshot(
    Map<String, dynamic> snapshot, {
    bool captureRecovery = true,
    String? onlyLanguage,
  }) async {
    final version = snapshot['version'];
    if (snapshot['format'] != 'korean-memo-backup' ||
        (version != 1 && version != 2)) {
      throw const FormatException('不支持的备份格式');
    }
    final payload = snapshot['tables'];
    if (payload is! Map) throw const FormatException('备份缺少数据');
    final columns = <String, List<String>>{
      for (final entry in _backupColumnsV1.entries)
        entry.key: _columnsFor(entry.key, version as int),
    };
    if (_aiColumnsV1.keys.any(payload.containsKey)) {
      if (!_aiColumnsV1.keys.every(payload.containsKey)) {
        throw const FormatException('AI 备份表不完整');
      }
      for (final entry in _aiColumnsV1.entries) {
        columns[entry.key] = _columnsFor(entry.key, version);
      }
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
    final language = onlyLanguage == null
        ? null
        : normalizeLearningLanguage(onlyLanguage);
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
      if (language == null) {
        await _restoreAllRows(columns, payload);
      } else {
        await _restoreOneLanguage(columns, payload, language, version);
      }
      for (final entry in localBackupSettings.entries) {
        await saveSetting(entry.key, entry.value);
      }
      await saveSetting('last_review_undo', null);
      await saveSetting(scopedSetting('ko', 'last_review_undo'), null);
      await saveSetting(scopedSetting('en', 'last_review_undo'), null);
      if (language == null) await _prefixLearningSettings();
      if (await loadSetting(activeLanguageSettingKey) == null) {
        await saveSetting(activeLanguageSettingKey, 'ko');
      }
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

  Future<void> _restoreAllRows(
    Map<String, List<String>> columns,
    Map<dynamic, dynamic> payload,
  ) async {
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
        await _insertBackupRow(table, columns[table]!, raw as Map);
      }
    }
  }

  Future<void> _restoreOneLanguage(
    Map<String, List<String>> columns,
    Map<dynamic, dynamic> payload,
    String language,
    int version,
  ) async {
    final wordRows = [
      for (final raw in payload['words'] as List)
        if (_rowLanguage(raw as Map, version) == language) raw,
    ];
    final bookRows = [
      for (final raw in payload['word_books'] as List)
        if (_rowLanguage(raw as Map, version) == language) raw,
    ];
    final backupWordIds = {for (final row in wordRows) row['id'] as int};
    final backupBookIds = {for (final row in bookRows) row['id'] as int};
    await customStatement(
      "DELETE FROM app_settings WHERE key LIKE ? OR key LIKE ? OR key LIKE ?",
      ['$language:%', 'checkin:$language:%', 'objective:$language:%'],
    );
    await customStatement(
      "DELETE FROM app_settings WHERE key IN ("
      "SELECT 'word_status:' || id FROM words WHERE language = ? "
      "UNION SELECT 'word_forms:' || id FROM words WHERE language = ? "
      "UNION SELECT 'correct_streak:' || id FROM words WHERE language = ?)",
      [language, language, language],
    );
    if (columns.containsKey('ai_suggestions')) {
      for (final table in [
        'ai_word_contents',
        'ai_task_items',
        'ai_suggestions',
        'ai_tasks',
      ]) {
        await customStatement('DELETE FROM $table WHERE language = ?', [
          language,
        ]);
      }
    }
    await customStatement(
      'DELETE FROM word_book_words WHERE word_id IN (SELECT id FROM words WHERE language = ?) OR word_book_id IN (SELECT id FROM word_books WHERE language = ?)',
      [language, language],
    );
    await customStatement(
      'DELETE FROM user_words WHERE word_id IN (SELECT id FROM words WHERE language = ?)',
      [language],
    );
    await customStatement('DELETE FROM review_logs WHERE language = ?', [
      language,
    ]);
    await customStatement('DELETE FROM study_cards WHERE language = ?', [
      language,
    ]);
    await customStatement('DELETE FROM daily_statistics WHERE language = ?', [
      language,
    ]);
    await customStatement('DELETE FROM words WHERE language = ?', [language]);
    await customStatement('DELETE FROM word_books WHERE language = ?', [
      language,
    ]);

    final wordIds = <int, int>{};
    for (final raw in wordRows) {
      final oldId = raw['id'] as int;
      wordIds[oldId] = await _insertBackupRow(
        'words',
        columns['words']!,
        raw,
        omit: {'id'},
      );
    }
    final bookIds = <int, int>{};
    for (final raw in bookRows) {
      final oldId = raw['id'] as int;
      bookIds[oldId] = await _insertBackupRow(
        'word_books',
        columns['word_books']!,
        raw,
        omit: {'id'},
      );
    }
    for (final raw in payload['word_book_words'] as List) {
      final row = raw as Map;
      final wordId = wordIds[row['word_id']];
      final bookId = bookIds[row['word_book_id']];
      if (wordId == null || bookId == null) continue;
      if (!backupWordIds.contains(row['word_id']) ||
          !backupBookIds.contains(row['word_book_id'])) {
        continue;
      }
      await customStatement(
        'INSERT INTO word_book_words (word_book_id, word_id, sort_order) VALUES (?, ?, ?)',
        [bookId, wordId, row['sort_order']],
      );
    }
    for (final raw in payload['user_words'] as List) {
      final row = raw as Map;
      final wordId = wordIds[row['word_id']];
      if (wordId == null) continue;
      await customStatement(
        'INSERT INTO user_words (word_id, is_favorite, is_difficult, note, correct_count, wrong_count, last_seen_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          wordId,
          row['is_favorite'],
          row['is_difficult'],
          row['note'],
          row['correct_count'],
          row['wrong_count'],
          row['last_seen_at'],
        ],
      );
    }
    final usedTokens = {
      for (final row in await customSelect(
        'SELECT submission_token FROM review_logs',
      ).get())
        row.read<String>('submission_token'),
    };
    for (final table in ['study_cards', 'review_logs']) {
      for (final raw in payload[table] as List) {
        final row = Map<String, Object?>.from(raw as Map);
        if (_rowLanguage(row, version) != language) continue;
        final wordId = wordIds[row['word_id']];
        if (wordId == null) continue;
        row['word_id'] = wordId;
        if (table == 'review_logs') {
          var token = row['submission_token']?.toString() ?? '';
          while (token.isEmpty || !usedTokens.add(token)) {
            token = '$token-$language-${usedTokens.length}';
          }
          row['submission_token'] = token;
        }
        await _insertBackupRow(table, columns[table]!, row, omit: {'id'});
      }
    }
    for (final raw in payload['daily_statistics'] as List) {
      final row = raw as Map;
      if (_rowLanguage(row, version) != language) continue;
      await _insertBackupRow(
        'daily_statistics',
        columns['daily_statistics']!,
        row,
      );
    }
    for (final raw in payload['app_settings'] as List) {
      final row = Map<String, Object?>.from(raw as Map);
      final key = _legacySettingKey(row['key'] as String);
      if (_excludedBackupSettings.contains(key) || key.startsWith('cloud_')) {
        continue;
      }
      final wordSetting = _wordSettingPattern.firstMatch(key);
      if (wordSetting != null) {
        final mapped = wordIds[int.parse(wordSetting.group(2)!)];
        if (mapped == null) continue;
        row['key'] = '${wordSetting.group(1)}:$mapped';
      } else if (_settingLanguage(key) != language) {
        continue;
      } else {
        row['key'] = key;
      }
      await _insertBackupRow('app_settings', columns['app_settings']!, row);
    }
    if (!columns.containsKey('ai_suggestions')) return;
    final suggestionIds = <String, String>{};
    final taskIds = <String, String>{};
    for (final raw in payload['ai_tasks'] as List) {
      final row = raw as Map;
      if (_rowLanguage(row, version) != language) continue;
      final oldId = row['id'] as String;
      taskIds[oldId] = await _insertBackupRow(
        'ai_tasks',
        columns['ai_tasks']!,
        row,
        replaceTextId: 'id',
      );
    }
    for (final raw in payload['ai_suggestions'] as List) {
      final row = raw as Map;
      if (_rowLanguage(row, version) != language) continue;
      final wordId = wordIds[row['word_id']];
      if (wordId == null) continue;
      final oldId = row['id'] as String;
      suggestionIds[oldId] = await _insertBackupRow(
        'ai_suggestions',
        columns['ai_suggestions']!,
        {...row, 'word_id': wordId},
        replaceTextId: 'id',
      );
    }
    for (final raw in payload['ai_task_items'] as List) {
      final row = raw as Map;
      if (_rowLanguage(row, version) != language) continue;
      final wordId = wordIds[row['word_id']];
      final taskId = taskIds[row['task_id']];
      if (wordId == null || taskId == null) continue;
      final suggestion = row['suggestion_id'];
      await _insertBackupRow('ai_task_items', columns['ai_task_items']!, {
        ...row,
        'word_id': wordId,
        'task_id': taskId,
        'suggestion_id': suggestion == null
            ? null
            : suggestionIds[suggestion] ?? suggestion,
      }, replaceTextId: 'id');
    }
    for (final raw in payload['ai_word_contents'] as List) {
      final row = raw as Map;
      if (_rowLanguage(row, version) != language) continue;
      final wordId = wordIds[row['word_id']];
      if (wordId == null) continue;
      await _insertBackupRow('ai_word_contents', columns['ai_word_contents']!, {
        ...row,
        'word_id': wordId,
      });
    }
  }

  String _rowLanguage(Map row, int version) => version < 2
      ? 'ko'
      : normalizeLearningLanguage(row['language'] as String?);

  /// Integer tables return the new row id. Text-id tables return the id string
  /// when [replaceTextId] is set.
  Future<dynamic> _insertBackupRow(
    String table,
    List<String> columns,
    Map raw, {
    Set<String> omit = const {},
    String? replaceTextId,
  }) async {
    final row = Map<String, Object?>.from(raw);
    if (replaceTextId != null) {
      row[replaceTextId] =
          '${row[replaceTextId] ?? 'row'}-${_backupIdSerial++}';
    }
    final names = [
      for (final name in columns)
        if (!omit.contains(name)) name,
    ];
    final values = [for (final name in names) row[name]];
    if (_backupLanguageTables.contains(table) && !names.contains('language')) {
      names.add('language');
      values.add('ko');
    }
    if (table == 'words' && !names.contains('ipa')) {
      names.add('ipa');
      values.add(null);
    }
    await customStatement(
      'INSERT INTO $table (${names.join(',')}) VALUES (${List.filled(names.length, '?').join(',')})',
      values,
    );
    if (replaceTextId != null) return row[replaceTextId];
    if (omit.contains('id')) {
      final id = await customSelect(
        'SELECT last_insert_rowid() AS id',
      ).getSingle();
      return id.read<int>('id');
    }
    return row['id'];
  }
}

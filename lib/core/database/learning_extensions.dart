part of 'app_database.dart';

enum QueueKind { mixed, newWords, reviews }
enum PracticeMode { cards, spelling, listening, cloze, forms }
enum StudyDirection { forward, reverse }

class SessionOptions {
  const SessionOptions({this.daily = true, this.target = 20,
    this.queue = QueueKind.mixed, this.filter = LibraryFilter.all,
    this.mode = PracticeMode.cards, this.direction = StudyDirection.forward,
    this.partOfSpeech = '', this.tag = ''});
  final bool daily;
  final int target;
  final QueueKind queue;
  final LibraryFilter filter;
  final PracticeMode mode;
  final StudyDirection direction;
  final String partOfSpeech;
  final String tag;
  String get key => jsonEncode([daily, queue.name, filter.name, mode.name,
    direction.name, partOfSpeech, tag]);
  String get storageKey => 'learning_session:$key';
  Map<String, Object> toJson() => {'daily': daily, 'target': target,
    'queue': queue.index, 'filter': filter.index, 'mode': mode.index,
    'direction': direction.index, 'pos': partOfSpeech, 'tag': tag};
  factory SessionOptions.fromJson(Map<String, dynamic> data) => SessionOptions(
    daily: data['daily'] == true, target: (data['target'] as int? ?? 20)<1 ? 20 : (data['target'] as int? ?? 20),
    queue: QueueKind.values[(data['queue'] as int? ?? 0).clamp(0, QueueKind.values.length - 1)],
    filter: LibraryFilter.values[(data['filter'] as int? ?? 0).clamp(0, LibraryFilter.values.length - 1)],
    mode: PracticeMode.values[(data['mode'] as int? ?? 0).clamp(0, PracticeMode.values.length - 1)],
    direction: StudyDirection.values[(data['direction'] as int? ?? 0).clamp(0, 1)],
    partOfSpeech: data['pos'] as String? ?? '', tag: data['tag'] as String? ?? '');
}

class SessionProgress {
  const SessionProgress(this.done, this.target, this.seen);
  final int done;
  final int target;
  final List<int> seen;
}

class CheckinSummary {
  const CheckinSummary(this.days, this.streak, this.longest);
  final Set<String> days;
  final int streak;
  final int longest;
}

String dayKey(DateTime value) => _dailyStatKey(value).toIso8601String().split('T').first;

extension LearningDatabase on AppDatabase {
  Future<bool> recoverPreviousRestore()async {
    final recovery=await (select(recoverySnapshots)..where((r)=>r.id.equals(1))).getSingleOrNull();
    if(recovery==null)return false;
    await restoreBackupSnapshot(jsonDecode(recovery.payload) as Map<String,dynamic>,captureRecovery:false);
    await delete(recoverySnapshots).go();return true;
  }
  Future<SessionProgress> loadSession(SessionOptions options, DateTime now) async {
    final raw = await loadSetting(options.storageKey);
    if (raw != null) {
      final data = jsonDecode(raw) as Map;
      if (data['day'] == dayKey(now)) {
        return SessionProgress(data['done'] as int, data['target'] as int,
          (data['seen'] as List).cast<int>());
      }
    }
    return SessionProgress(0, options.target, const []);
  }

  Future<void> startSession(SessionOptions options, DateTime now) async {
    if (options.target < 1) throw const FormatException('本轮数量必须大于 0');
    await saveSetting(options.storageKey, jsonEncode({'day': dayKey(now),
      'done': 0, 'target': options.target, 'seen': <int>[]}));
    await saveSetting('selected_learning_session', jsonEncode({
      ...options.toJson(), 'day': dayKey(now)}));
  }

  Future<Word?> nextTrainingWord(SessionOptions options, DateTime now) async {
    final session = await loadSession(options, now);
    if (!options.daily && session.done >= session.target) return null;
    final variables = <Variable>[];
    final where = <String>[
      "NOT EXISTS (SELECT 1 FROM app_settings a WHERE a.key='word_status:' || w.id AND a.value IN ('suspended','known'))",
    ];
    if (options.filter == LibraryFilter.favorites) where.add('u.is_favorite=1');
    if (options.filter == LibraryFilter.wrong) where.add('u.is_difficult=1');
    if (options.partOfSpeech.isNotEmpty) {
      where.add('w.part_of_speech=?'); variables.add(Variable<String>(options.partOfSpeech));
    }
    if (options.tag.isNotEmpty) {
      where.add('(w.tags LIKE ? OR w.category LIKE ?)'); variables.addAll([Variable<String>('%${options.tag}%'),Variable<String>('%${options.tag}%')]);
    }
    if (!options.daily && session.seen.isNotEmpty) {
      where.add('w.id NOT IN (${List.filled(session.seen.length, '?').join(',')})');
      variables.addAll(session.seen.map(Variable<int>.new));
    }
    if (options.mode == PracticeMode.cloze) {
      where.add("w.example_ko IS NOT NULL AND instr(w.example_ko,CASE WHEN instr(w.korean,' / ')>0 THEN substr(w.korean,instr(w.korean,' / ')+3) ELSE w.korean END)>0");
    }
    if (options.mode == PracticeMode.forms) {
      where.add("EXISTS (SELECT 1 FROM app_settings a WHERE a.key='word_forms:' || w.id AND a.value!='')");
    }
    final due = now.toUtc();
    if (options.daily) {
      final plan = await loadDailyPlanProgress(now);
      final round = await loadStudyRoundProgress(now);
      final fresh = plan.newWordsDone < round.baseline + round.target;
      final review = plan.reviewsDone < plan.settings.reviewsPerDay;
      where.add('(${fresh ? 's.id IS NULL' : '0'} OR ${review ? 's.due<=?' : '0'})');
      if (review) variables.add(Variable<DateTime>(due));
    } else if (options.queue == QueueKind.newWords) {
      where.add('s.id IS NULL');
    } else if (options.queue == QueueKind.reviews) {
      where.add('s.due<=?'); variables.add(Variable<DateTime>(due));
    } else if (options.filter == LibraryFilter.all && options.partOfSpeech.isEmpty &&
        options.tag.isEmpty && options.mode == PracticeMode.cards) {
      where.add('(s.id IS NULL OR s.due<=?)'); variables.add(Variable<DateTime>(due));
    }
    final row = await customSelect(
      'SELECT w.id FROM words w LEFT JOIN study_cards s ON s.word_id=w.id '
      'LEFT JOIN user_words u ON u.word_id=w.id WHERE ${where.join(' AND ')} '
      'ORDER BY CASE WHEN s.id IS NULL THEN 1 ELSE 0 END, s.due, w.id LIMIT 1',
      variables: variables, readsFrom: {words, studyCards, userWords, appSettings},
    ).getSingleOrNull();
    if (row == null) return null;
    return (select(words)..where((w) => w.id.equals(row.read<int>('id')))).getSingle();
  }

  Future<Map<String, Object?>> captureReviewUndo(int wordId, DateTime date, SessionOptions? options) async {
    Future<Map<String, Object?>?> row(String table, String field, Object value) async {
      final result = await customSelect('SELECT * FROM $table WHERE $field=?',
        variables: [value is DateTime ? Variable<DateTime>(value) : Variable<int>(value as int)]).getSingleOrNull();
      return result?.data;
    }
    return {'wordId': wordId, 'day': dayKey(date),
      'card': await row('study_cards', 'word_id', wordId),
      'user': await row('user_words', 'word_id', wordId),
      'statistics': await row('daily_statistics', 'date', _dailyStatKey(date)),
      'settings': {for (final key in ['correct_streak:$wordId', 'checkin:${dayKey(date)}',
        'objective:${dayKey(date)}', if (options != null) options.storageKey]) key: await loadSetting(key)}};
  }

  Future<void> finishLearningReview(int id, int rating, DateTime date, String token,
      Map<String, Object?> undo, SessionOptions? options) async {
    final streak = rating >= 3 ? (int.tryParse(await loadSetting('correct_streak:$id') ?? '') ?? 0) + 1 : 0;
    await saveSetting('correct_streak:$id', '$streak');
    if (streak >= 3) {
      await (update(userWords)..where((word) => word.wordId.equals(id)))
        .write(const UserWordsCompanion(isDifficult: Value(false)));
    }
    if (options != null) {
      final progress = await loadSession(options, date);
      await saveSetting(options.storageKey, jsonEncode({'day': dayKey(date),
        'done': progress.done + 1, 'target': progress.target, 'seen': [...progress.seen, id]}));
      if (options.mode != PracticeMode.cards) {
        final key = 'objective:${dayKey(date)}';
        final raw = await loadSetting(key);
        final value = raw == null ? <String,dynamic>{'correct':0,'total':0} : jsonDecode(raw) as Map<String,dynamic>;
        await saveSetting(key,jsonEncode({'correct': (value['correct'] as int)+(rating>=3?1:0), 'total': (value['total'] as int)+1}));
      }
    }
    if (await loadSetting('auto_checkin') != 'false') { await checkIn(date); }
    await saveSetting('last_review_undo', jsonEncode({...undo, 'token': token}));
  }

  Future<Word?> undoLastReview(DateTime now) => transaction(() async {
    final raw = await loadSetting('last_review_undo');
    if (raw == null) return null;
    final undo = jsonDecode(raw) as Map<String, dynamic>;
    if (undo['day'] != dayKey(now)) { throw const FormatException('只能撤销今天最近的一次评分'); }
    final latest = await (select(reviewLogs)..orderBy([(r) => OrderingTerm.desc(r.id)])..limit(1)).getSingleOrNull();
    if (latest == null || latest.submissionToken != undo['token']) { throw const FormatException('评分记录已经变更，不能撤销'); }
    final id = undo['wordId'] as int;
    await (delete(reviewLogs)..where((r) => r.id.equals(latest.id))).go();
    for (final table in ['study_cards', 'user_words']) {
      await customStatement('DELETE FROM $table WHERE word_id=?', [id]);
      final data = undo[table == 'study_cards' ? 'card' : 'user'] as Map?;
      if (data != null) { await _insertSnapshotRow(table, data); }
    }
    await (delete(dailyStatistics)..where((r) => r.date.equals(_dailyStatKey(now)))).go();
    if (undo['statistics'] != null) { await _insertSnapshotRow('daily_statistics', undo['statistics'] as Map); }
    for (final entry in (undo['settings'] as Map).entries) {
      if((entry.key as String).startsWith('checkin:')&&entry.value==null&&
          (await loadDailyPlanProgress(now)).totalDone>0) { continue; }
      await saveSetting(entry.key as String, entry.value as String?);
    }
    await saveSetting('last_review_undo', null);
    return (select(words)..where((w) => w.id.equals(id))).getSingleOrNull();
  });

  Future<void> _insertSnapshotRow(String table, Map row) => customStatement(
    'INSERT INTO $table (${row.keys.join(',')}) VALUES (${List.filled(row.length, '?').join(',')})', row.values.toList());

  Future<void> checkIn(DateTime now) async {
    if ((await loadDailyPlanProgress(now)).totalDone == 0) {
      throw const FormatException('完成至少一次学习后即可打卡');
    }
    final key = 'checkin:${dayKey(now)}';
    if (await loadSetting(key) == null) { await saveSetting(key, now.toUtc().toIso8601String()); }
  }

  Future<CheckinSummary> loadCheckins(DateTime now) async {
    final rows = await (select(appSettings)..where((r) => r.key.like('checkin:%'))).get();
    final days = rows.map((r) => r.key.substring(8)).toSet();
    var cursor = _dailyStatKey(now);
    if (!days.contains(dayKey(cursor))) { cursor = cursor.subtract(const Duration(days: 1)); }
    var streak = 0;
    while (days.contains(dayKey(cursor))) { streak++; cursor = cursor.subtract(const Duration(days: 1)); }
    var longest = 0, current = 0;
    DateTime? previous;
    final sorted = days.toList()..sort();
    for (final day in sorted) {
      final date = DateTime.parse('${day}T00:00:00Z');
      current = previous != null && date.difference(previous).inDays == 1 ? current + 1 : 1;
      if (current > longest) longest = current;
      previous = date;
    }
    return CheckinSummary(days, streak, longest);
  }

  Future<List<Map<String, Object?>>> reviewForecast(DateTime now) async {
    final result = <Map<String, Object?>>[];
    final statuses=await (select(appSettings)..where((r)=>r.key.like('word_status:%'))).get();
    final excluded=statuses.where((r)=>r.value=='known'||r.value=='suspended').map((r)=>int.tryParse(r.key.substring(12))).toSet();
    for (var i = 0; i < 7; i++) {
      final start = DateTime(now.year, now.month, now.day + i).toUtc();
      final end = DateTime(now.year, now.month, now.day + i + 1).toUtc();
      final rows = await (select(studyCards)..where((r) =>
        (i == 0 ? const Constant<bool>(true) : r.due.isBiggerOrEqualValue(start)) & r.due.isSmallerThanValue(end))).get();
      result.add({'day': dayKey(DateTime(now.year, now.month, now.day + i)), 'count': rows.where((r)=>!excluded.contains(r.wordId)).length});
    }
    return result;
  }

  Future<void> batchAnnotate(List<int> ids, {String? partOfSpeech, String? tag}) => transaction(() async {
    for (final id in ids) {
      final word = await (select(words)..where((w) => w.id.equals(id))).getSingle();
      await updateWord(wordId: id, korean: word.korean, meaningZh: word.meaningZh,
        partOfSpeech: partOfSpeech, tags: tag == null ? null : {if(word.tags?.isNotEmpty==true)word.tags!,tag}.join(', '));
    }
  });
}

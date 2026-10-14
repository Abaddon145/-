import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/missing_meaning.dart';
import '../domain/ai_models.dart';

class AiConflict extends AiException {
  const AiConflict(this.current) : super('conflict');
  final Word current;
}

class AiRepository {
  AiRepository(this.db);
  final AppDatabase db;
  Future<Word?> word(int id) =>
      (db.select(db.words)..where((r) => r.id.equals(id))).getSingleOrNull();
  Future<AiSuggestionRecord?> record(String id) => (db.select(
    db.aiSuggestions,
  )..where((r) => r.id.equals(id))).getSingleOrNull();
  Future<Map<String, String>> contents(Word word) async {
    final rows = await (db.select(
      db.aiWordContents,
    )..where((r) => r.wordId.equals(word.id))).get();
    return {
      for (final row in rows)
        if (row.originalSnapshot == aiSnapshotJson(word)) row.field: row.value,
    };
  }

  Future<AiSuggestion?> cached(AiRequest request) async {
    final row =
        await (db.select(db.aiSuggestions)
              ..where(
                (r) =>
                    r.cacheKey.equals(
                      aiCacheKey(
                        request.word,
                        request.context,
                        request.type,
                        request.style,
                        request.exampleCount,
                      ),
                    ) &
                    r.savedFields.equals('[]'),
              )
              ..orderBy([(r) => OrderingTerm.desc(r.createdAt)])
              ..limit(1))
            .getSingleOrNull();
    if (row == null ||
        DateTime.now().toUtc().difference(row.createdAt.toUtc()) >
            const Duration(days: 30) ||
        row.originalSnapshot != aiSnapshotJson(request.word)) {
      return null;
    }
    try {
      final result = AiSuggestion.fromJson(
        jsonDecode(row.payload) as Map<String, dynamic>,
      );
      if (result.wordId != request.word.id ||
          result.requestId != row.id ||
          result.context != request.context ||
          result.result['originalTerm'] != request.word.korean) {
        return null;
      }
      return result;
    } on AiException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<void> store(
    AiRequest request,
    AiSuggestion suggestion, {
    String? itemId,
  }) async {
    // Validate again at the write boundary, including when the gateway is mocked.
    AiSuggestion.fromJson(
      suggestion.toJson().cast<String, dynamic>(),
      request: request,
    );
    await db.transaction(() async {
      await db
          .into(db.aiSuggestions)
          .insert(
            AiSuggestionsCompanion.insert(
              id: suggestion.requestId,
              wordId: suggestion.wordId,
              originalSnapshot: aiSnapshotJson(request.word),
              cacheKey: aiCacheKey(
                request.word,
                request.context,
                request.type,
                request.style,
                request.exampleCount,
              ),
              taskType: request.type,
              context: request.context,
              payload: jsonEncode(suggestion.toJson()),
              createdAt: DateTime.now().toUtc(),
            ),
          );
      if (itemId != null) {
        await (db.update(
          db.aiTaskItems,
        )..where((r) => r.id.equals(itemId))).write(
          AiTaskItemsCompanion(
            status: const Value('awaitingReview'),
            suggestionId: Value(suggestion.requestId),
            errorCode: const Value(null),
          ),
        );
      }
    });
  }

  Future<void> save(
    String id,
    AiSuggestion edited,
    Set<String> fields, {
    String? expectedSnapshot,
    String? spelling,
    bool spellingConfirmed = false,
    String? itemId,
  }) => db.transaction(() async {
    final saved = await record(id);
    if (saved == null) throw const AiException('invalid_response');
    final original = AiSuggestion.fromJson(
      jsonDecode(saved.payload) as Map<String, dynamic>,
    );
    final snapshot = jsonDecode(saved.originalSnapshot) as Map;
    if (original.wordId != saved.wordId ||
        original.requestId != saved.id ||
        original.result['originalTerm'] != snapshot['originalTerm'] ||
        snapshot['wordId'] != saved.wordId) {
      throw const AiException('identity_mismatch');
    }
    AiSuggestion.fromJson(edited.toJson().cast<String, dynamic>());
    if (edited.requestId != id ||
        edited.wordId != saved.wordId ||
        edited.result['originalTerm'] != original.result['originalTerm'] ||
        edited.context != original.context ||
        edited.model != original.model ||
        edited.generatedAt != original.generatedAt ||
        edited.promptVersion != original.promptVersion) {
      throw const AiException('identity_mismatch');
    }
    if (saved.savedFields != '[]') throw const AiException('already_saved');
    if (fields.any((key) => !aiFieldLabels.containsKey(key)) ||
        (fields.isEmpty && spelling == null)) {
      throw const AiException('invalid_response');
    }
    final current = await word(saved.wordId);
    if (current == null) throw const AiException('deleted');
    if (aiSnapshotJson(current) !=
        (expectedSnapshot ?? saved.originalSnapshot)) {
      throw AiConflict(current);
    }
    if (spelling != null &&
        (!spellingConfirmed ||
            spelling.trim().isEmpty ||
            !original.spellings.contains(spelling))) {
      throw const AiException('invalid_response');
    }
    final newTerm = spelling ?? current.korean;
    final newBase = fields.contains('baseForm')
        ? edited.fieldText('baseForm')
        : current.baseForm;
    final duplicates =
        await (db.select(db.words)..where(
              (r) =>
                  r.id.isNotValue(current.id) &
                  r.normalizedKorean.equals(normalizeLookup(newTerm)) &
                  r.normalizedBaseForm.equals(normalizeLookup(newBase)),
            ))
            .get();
    if (duplicates.isNotEmpty) throw const AiException('duplicate');
    final hasWordFields =
        fields.any(
          (k) => [
            'meaningZh',
            'partOfSpeech',
            'baseForm',
            'exampleKo',
            'exampleZh',
          ].contains(k),
        ) ||
        spelling != null;
    if (hasWordFields) {
      await (db.update(db.words)..where((r) => r.id.equals(current.id))).write(
        WordsCompanion(
          korean: spelling == null ? const Value.absent() : Value(newTerm),
          normalizedKorean: spelling == null
              ? const Value.absent()
              : Value(normalizeLookup(newTerm)),
          baseForm: fields.contains('baseForm')
              ? Value(newBase)
              : const Value.absent(),
          normalizedBaseForm: fields.contains('baseForm')
              ? Value(normalizeLookup(newBase))
              : const Value.absent(),
          meaningZh: fields.contains('meaningZh')
              ? Value(edited.fieldText('meaningZh'))
              : const Value.absent(),
          partOfSpeech: fields.contains('partOfSpeech')
              ? Value(edited.fieldText('partOfSpeech'))
              : const Value.absent(),
          exampleKo: fields.contains('exampleKo')
              ? Value(edited.fieldText('exampleKo'))
              : const Value.absent(),
          exampleZh: fields.contains('exampleZh')
              ? Value(edited.fieldText('exampleZh'))
              : const Value.absent(),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
    }
    final confirmedSnapshot = aiSnapshotJson((await word(current.id))!);
    // Preserve still-valid, previously confirmed independent fields after an AI word update.
    await (db.update(db.aiWordContents)..where(
          (r) =>
              r.wordId.equals(current.id) &
              r.originalSnapshot.equals(aiSnapshotJson(current)),
        ))
        .write(
          AiWordContentsCompanion(originalSnapshot: Value(confirmedSnapshot)),
        );
    for (final field in {...fields, if (spelling != null) 'spelling'}) {
      await db
          .into(db.aiWordContents)
          .insertOnConflictUpdate(
            AiWordContentsCompanion.insert(
              wordId: current.id,
              field: field,
              value: field == 'spelling' ? spelling! : edited.fieldText(field),
              requestId: id,
              model: original.model,
              promptVersion: original.promptVersion,
              originalSnapshot: confirmedSnapshot,
              generatedAt: original.generatedAt,
              confirmedAt: DateTime.now().toUtc(),
            ),
          );
    }
    await (db.update(db.aiSuggestions)..where((r) => r.id.equals(id))).write(
      AiSuggestionsCompanion(
        savedFields: Value(
          jsonEncode([...fields, if (spelling != null) 'spelling']),
        ),
        payload: Value(jsonEncode(edited.toJson())),
      ),
    );
    await (db.update(db.aiTaskItems)..where((r) => r.suggestionId.equals(id)))
        .write(const AiTaskItemsCompanion(status: Value('saved')));
    if (itemId != null) {
      final item = await (db.select(
        db.aiTaskItems,
      )..where((r) => r.id.equals(itemId))).getSingleOrNull();
      if (item == null || item.wordId != saved.wordId) {
        throw const AiException('identity_mismatch');
      }
      await (db.update(
        db.aiTaskItems,
      )..where((r) => r.id.equals(itemId))).write(
        AiTaskItemsCompanion(
          status: const Value('saved'),
          suggestionId: Value(id),
        ),
      );
    }
  });
  Future<String> createTask(List<Word> words, String context) async {
    final unique = {for (final w in words) w.id: w}.values.toList();
    if (unique.isEmpty ||
        unique.length > 20 ||
        unique.any((w) => !isMissingMeaning(w.meaningZh))) {
      throw const AiException('batch_limit');
    }
    if (context.trim().isEmpty || context.length > 600) {
      throw const AiException('invalid_response');
    }
    final id = const Uuid().v4(), now = DateTime.now().toUtc();
    await db.transaction(() async {
      await db
          .into(db.aiTasks)
          .insert(
            AiTasksCompanion.insert(
              id: id,
              context: context,
              createdAt: now,
              updatedAt: now,
            ),
          );
      for (final w in unique) {
        await db
            .into(db.aiTaskItems)
            .insert(
              AiTaskItemsCompanion.insert(
                id: const Uuid().v4(),
                taskId: id,
                wordId: w.id,
                originalSnapshot: aiSnapshotJson(w),
              ),
            );
      }
    });
    return id;
  }

  Stream<List<AiTaskRecord>> watchTasks() => (db.select(
    db.aiTasks,
  )..orderBy([(r) => OrderingTerm.desc(r.createdAt)])).watch();
  Stream<List<AiTaskItemRecord>> watchItems(String taskId) => (db.select(
    db.aiTaskItems,
  )..where((r) => r.taskId.equals(taskId))).watch();
  Future<List<AiTaskItemRecord>> items(String taskId) =>
      (db.select(db.aiTaskItems)..where((r) => r.taskId.equals(taskId))).get();
  Future<void> recoverInterrupted() => db.transaction(() async {
    await (db.update(db.aiTasks)..where((r) => r.status.equals('running')))
        .write(const AiTasksCompanion(status: Value('paused')));
    await (db.update(db.aiTaskItems)..where((r) => r.status.equals('running')))
        .write(const AiTaskItemsCompanion(status: Value('queued')));
  });
  Future<void> clearCache() async {
    final linked = (await db.select(db.aiTaskItems).get())
        .map((r) => r.suggestionId)
        .whereType<String>()
        .toSet();
    await (db.delete(
      db.aiSuggestions,
    )..where((r) => r.savedFields.equals('[]') & r.id.isNotIn(linked))).go();
  }
}

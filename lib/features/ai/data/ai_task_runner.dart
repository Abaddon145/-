import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/missing_meaning.dart';
import '../domain/ai_models.dart';
import 'ai_client.dart';
import 'ai_repository.dart';

class AiTaskRunner {
  AiTaskRunner(this.repository, this.gateway) {
    ready = repository.recoverInterrupted();
  }
  final AiRepository repository;
  final AiGateway Function() gateway;
  late final Future<void> ready;
  String? _active;
  AiCancellation? _cancel;
  Future<void>? _running;
  bool get isRunning => _active != null;
  bool active(String taskId) => _active == taskId;
  Future<void> start(String taskId) {
    if (isRunning) throw const AiException('busy');
    _active = taskId;
    _cancel = AiCancellation();
    final future = _run(taskId, _cancel!);
    _running = future;
    return future;
  }

  Future<void> cancelAll() async {
    _cancel?.cancel();
    await _running;
  }

  void dispose() => _cancel?.cancel();
  Future<void> _run(String taskId, AiCancellation cancel) async {
    final db = repository.db;
    try {
      await ready;
      final task = await (db.select(
        db.aiTasks,
      )..where((r) => r.id.equals(taskId))).getSingleOrNull();
      if (task == null) throw const AiException('invalid_response');
      final client = gateway();
      await (db.update(db.aiTasks)..where((r) => r.id.equals(taskId))).write(
        AiTasksCompanion(
          status: const Value('running'),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
      final pending = (await repository.items(taskId))
          .where(
            (r) => [
              'queued',
              'running',
              'failed',
              'cancelled',
              'conflict',
            ].contains(r.status),
          )
          .toList();
      var next = 0;
      Future<void> worker() async {
        while (!cancel.cancelled && next < pending.length) {
          final item = pending[next++];
          try {
            final word = await repository.word(item.wordId);
            if (word == null) throw const AiException('deleted');
            if (aiSnapshotJson(word) != item.originalSnapshot ||
                !isMissingMeaning(word.meaningZh)) {
              throw const AiException('conflict');
            }
            cancel.check();
            await (db.update(
              db.aiTaskItems,
            )..where((r) => r.id.equals(item.id))).write(
              AiTaskItemsCompanion(
                status: const Value('running'),
                errorCode: const Value(null),
                attempts: Value(item.attempts + 1),
              ),
            );
            final request = AiRequest(
              requestId: const Uuid().v4(),
              word: word,
              context: task.context,
              type: 'complete',
            );
            final result = await client.generate(request, cancel);
            cancel.check();
            await repository.store(request, result, itemId: item.id);
          } catch (error) {
            final code = cancel.cancelled
                ? 'cancelled'
                : error is AiException
                ? error.code
                : 'provider_error';
            await (db.update(
              db.aiTaskItems,
            )..where((r) => r.id.equals(item.id))).write(
              AiTaskItemsCompanion(
                status: Value(
                  code == 'cancelled'
                      ? 'cancelled'
                      : ['conflict', 'deleted'].contains(code)
                      ? 'conflict'
                      : 'failed',
                ),
                errorCode: Value(code),
              ),
            );
          }
        }
      }

      // Two client workers update only their own rows; server independently limits actual calls.
      await Future.wait([worker(), worker()]);
      if (cancel.cancelled) {
        await (db.update(db.aiTaskItems)..where(
              (r) =>
                  r.taskId.equals(taskId) &
                  r.status.isIn(['queued', 'running', 'failed']),
            ))
            .write(
              const AiTaskItemsCompanion(
                status: Value('cancelled'),
                errorCode: Value('cancelled'),
              ),
            );
      }
      final items = await repository.items(taskId);
      final incomplete = items.any(
        (r) => [
          'queued',
          'failed',
          'conflict',
          'running',
          'cancelled',
        ].contains(r.status),
      );
      await (db.update(db.aiTasks)..where((r) => r.id.equals(taskId))).write(
        AiTasksCompanion(
          status: Value(
            cancel.cancelled
                ? 'cancelled'
                : incomplete
                ? 'paused'
                : 'completed',
          ),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
    } finally {
      _active = null;
      _cancel = null;
      _running = null;
    }
  }

  Future<void> confirmItemSnapshot(String itemId) async {
    if (isRunning) throw const AiException('busy');
    final db = repository.db;
    final item = await (db.select(
      db.aiTaskItems,
    )..where((r) => r.id.equals(itemId))).getSingle();
    final current = await repository.word(item.wordId);
    if (current == null) throw const AiException('deleted');
    if (!isMissingMeaning(current.meaningZh)) {
      throw const AiException('conflict');
    }
    await (db.update(db.aiTaskItems)..where((r) => r.id.equals(itemId))).write(
      AiTaskItemsCompanion(
        originalSnapshot: Value(aiSnapshotJson(current)),
        status: const Value('queued'),
        errorCode: const Value(null),
      ),
    );
  }
}

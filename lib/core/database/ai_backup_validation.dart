import 'dart:convert';
import '../../features/ai/domain/ai_response.dart';

/// Validate optional AI rows before any restore deletes the current database.
/// Deleted source words are allowed in task/suggestion audit records.
void validateAiBackup(Map payload) {
  Map<String, dynamic> snapshot(Object? text, int wordId) {
    if (text is! String || text.length > 20000) {
      throw const FormatException('AI 快照无效');
    }
    final data = jsonDecode(text);
    if (data is! Map<String, dynamic> ||
        data['wordId'] != wordId ||
        data['originalTerm'] is! String ||
        data['meaningZh'] is! String) {
      throw const FormatException('AI 快照无效');
    }
    return data;
  }

  try {
    final suggestions = <String, Map>{};
    for (final raw in payload['ai_suggestions'] as List) {
      final r = raw as Map;
      final data = snapshot(r['original_snapshot'], r['word_id'] as int);
      final result = AiSuggestion.fromJson(
        jsonDecode(r['payload'] as String) as Map<String, dynamic>,
      );
      final fields = jsonDecode(r['saved_fields'] as String);
      if (result.requestId != r['id'] ||
          result.wordId != r['word_id'] ||
          result.result['originalTerm'] != data['originalTerm'] ||
          result.context != r['context'] ||
          !['complete', 'explain'].contains(r['task_type']) ||
          fields is! List ||
          fields.any((f) => f != 'spelling' && !aiFieldLabels.containsKey(f))) {
        throw const FormatException('AI 建议无效');
      }
      suggestions[r['id'] as String] = r;
    }
    final taskIds = <String>{};
    for (final raw in payload['ai_tasks'] as List) {
      final r = raw as Map;
      if (r['id'] is! String ||
          r['context'] is! String ||
          (r['context'] as String).length > 600 ||
          ![
            'paused',
            'running',
            'completed',
            'cancelled',
          ].contains(r['status'])) {
        throw const FormatException('AI 任务无效');
      }
      taskIds.add(r['id'] as String);
    }
    for (final raw in payload['ai_task_items'] as List) {
      final r = raw as Map;
      snapshot(r['original_snapshot'], r['word_id'] as int);
      final linked = r['suggestion_id'] == null
          ? null
          : suggestions[r['suggestion_id']];
      if (!taskIds.contains(r['task_id']) ||
          r['attempts'] is! int ||
          (r['attempts'] as int) < 0 ||
          ![
            'queued',
            'running',
            'awaitingReview',
            'failed',
            'cancelled',
            'saved',
            'conflict',
          ].contains(r['status']) ||
          (r['suggestion_id'] != null &&
              (linked == null || linked['word_id'] != r['word_id']))) {
        throw const FormatException('AI 任务条目无效');
      }
    }
    for (final raw in payload['ai_word_contents'] as List) {
      final r = raw as Map;
      snapshot(r['original_snapshot'], r['word_id'] as int);
      if ((!aiFieldLabels.containsKey(r['field']) &&
              r['field'] != 'spelling') ||
          r['value'] is! String ||
          (r['value'] as String).length > 3006 ||
          r['model'] is! String ||
          (r['model'] as String).length > 200 ||
          r['request_id'] is! String) {
        throw const FormatException('AI 确认内容无效');
      }
    }
  } catch (_) {
    throw const FormatException('AI 备份数据无效，当前数据保持不变');
  }
}

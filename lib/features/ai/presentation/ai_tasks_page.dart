import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/database/app_database.dart';
import '../domain/ai_models.dart';
import '../domain/ai_providers.dart';
import 'ai_assistant_sheet.dart';

String aiStatus(String status) =>
    const {
      'paused': '待继续',
      'running': '生成中',
      'completed': '生成完成',
      'queued': '排队中',
      'awaitingReview': '成功·待确认',
      'failed': '失败',
      'cancelled': '已取消',
      'saved': '已保存',
      'conflict': '原词冲突',
    }[status] ??
    status;

class AiTasksPage extends ConsumerWidget {
  const AiTasksPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(aiTaskRunnerProvider);
    final tasks = ref.watch(aiTasksProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('本机 AI 任务')),
      body: SafeArea(
        child: tasks.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (rows) => rows.isEmpty
              ? const Center(child: Text('在词库勾选待补中文的词，创建一批任务。'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text('未完成任务由你决定继续。成功建议已经逐条保存在本机。'),
                    for (final task in rows)
                      Card(
                        child: ListTile(
                          title: Text(task.context),
                          subtitle: Text(
                            '${aiStatus(task.status)} · ${task.createdAt.toLocal().toString().substring(0, 16)}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/ai/tasks/${task.id}'),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class AiTaskPage extends ConsumerStatefulWidget {
  const AiTaskPage({super.key, required this.taskId});
  final String taskId;
  @override
  ConsumerState<AiTaskPage> createState() => _AiTaskPageState();
}

class _AiTaskPageState extends ConsumerState<AiTaskPage> {
  String? _error;
  Future<void> _start() async {
    final runner = ref.read(aiTaskRunnerProvider);
    setState(() => _error = null);
    try {
      await runner.start(widget.taskId);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _review(AiTaskItemRecord item) async {
    final repo = ref.read(aiRepositoryProvider);
    final word = await repo.word(item.wordId);
    final row = item.suggestionId == null
        ? null
        : await repo.record(item.suggestionId!);
    if (!mounted) return;
    if (word == null) {
      setState(() => _error = const AiException('deleted').message);
      return;
    }
    if (row != null) {
      try {
        final suggestion = AiSuggestion.fromJson(
          jsonDecode(row.payload) as Map<String, dynamic>,
        );
        await showAiAssistant(
          context,
          word,
          suggestion: suggestion,
          batch: true,
          taskItemId: item.id,
        );
      } catch (error) {
        if (mounted) setState(() => _error = '$error');
      }
      return;
    }
    if (item.status == 'conflict') {
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('重新确认当前词条'),
              content: SingleChildScrollView(
                child: Text(
                  '原快照：${item.originalSnapshot}\n\n当前词：${word.korean}\n当前中文：${word.meaningZh}\n仅仍缺中文的词可重新排队。',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('确认后重新排队'),
                ),
              ],
            ),
          ) ==
          true;
      if (!mounted || !confirmed) return;
      try {
        await ref.read(aiTaskRunnerProvider).confirmItemSnapshot(item.id);
      } catch (e) {
        if (mounted) setState(() => _error = '$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final runner = ref.watch(aiTaskRunnerProvider),
        items = ref.watch(aiItemsProvider(widget.taskId));
    final task = ref
        .watch(aiTasksProvider)
        .valueOrNull
        ?.where((t) => t.id == widget.taskId)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('AI 批量进度与审核')),
      body: SafeArea(
        child: items.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (rows) {
            final completed = rows
                .where(
                  (r) => [
                    'awaitingReview',
                    'saved',
                    'failed',
                    'conflict',
                    'cancelled',
                  ].contains(r.status),
                )
                .length;
            final running =
                task?.status == 'running' ||
                rows.any((r) => r.status == 'running');
            return ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Text(task?.context ?? '读取语境…'),
                const Text('每任务最多 20 个词。生成后仍需逐条审核并选择保存。'),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: rows.isEmpty ? 0 : completed / rows.length,
                ),
                Text(
                  '$completed / ${rows.length} 已处理 · ${rows.where((r) => r.status == 'awaitingReview').length} 待确认 · ${rows.where((r) => r.status == 'saved').length} 已保存',
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed:
                          running ||
                              !rows.any(
                                (r) => [
                                  'queued',
                                  'failed',
                                  'cancelled',
                                ].contains(r.status),
                              )
                          ? null
                          : _start,
                      child: const Text('开始 / 仅重试失败及未完成'),
                    ),
                    TextButton(
                      onPressed: running
                          ? () async {
                              await runner.cancelAll();
                            }
                          : null,
                      child: const Text('取消排队与请求'),
                    ),
                  ],
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                for (final item in rows)
                  Card(
                    child: ListTile(
                      title: Text(
                        (jsonDecode(item.originalSnapshot)
                                as Map)['originalTerm']
                            as String,
                      ),
                      subtitle: Text(
                        '${aiStatus(item.status)}${item.errorCode == null ? '' : '\n${AiException(item.errorCode!).message}'}',
                      ),
                      trailing:
                          item.status == 'awaitingReview' ||
                              item.status == 'conflict'
                          ? const Icon(Icons.edit_note)
                          : null,
                      onTap:
                          ['awaitingReview', 'conflict'].contains(item.status)
                          ? () => _review(item)
                          : null,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

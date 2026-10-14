import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/missing_meaning.dart';
import '../../study/domain/providers.dart';
import '../../study/presentation/study_controller.dart';
import '../../study/presentation/session_sheet.dart';
import '../../statistics/domain/providers.dart';
import '../../ai/domain/ai_models.dart';
import '../../ai/domain/ai_providers.dart';
import '../../ai/presentation/ai_context_picker.dart';
import '../domain/providers.dart';
import 'word_editor_sheet.dart';
import 'word_detail_sheet.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});
  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final _selected = <int>{};
  bool _creating = false;
  void _refresh() {
    ref.invalidate(libraryWordsProvider);
    ref.invalidate(homeCountsProvider);
    ref.invalidate(wordBooksProvider);
    ref.invalidate(studyBookCountsProvider);
    ref.invalidate(dailyPlanProgressProvider);
    ref.invalidate(studyRoundProgressProvider);
    ref.invalidate(studyControllerProvider);
  }

  Future<void> _edit({Word? word}) async {
    final saved = await showWordEditor(context, word: word);
    if (mounted && saved == true) {
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(word == null ? '单词已加入词库' : '词条已更新')),
      );
    }
  }

  Future<void> _delete(LibraryWordEntry item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除词条？'),
        content: Text('“${item.word.korean}”的复习记录和学习状态也会被删除，此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    try {
      await ref.read(databaseProvider).deleteWord(item.word.id);
      if (!mounted) return;
      setState(() => _selected.remove(item.word.id));
      _refresh();
      ref.invalidate(recentStatisticsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除失败：$e')));
      }
    }
  }

  Future<void> _annotate(List<LibraryWordEntry> items) async {
    final pos = TextEditingController(), tag = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('批量标记 ${items.length} 个词'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pos,
                decoration: const InputDecoration(labelText: '词性（留空保留）'),
              ),
              TextField(
                controller: tag,
                decoration: const InputDecoration(labelText: '追加标签（留空保留）'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('应用'),
          ),
        ],
      ),
    );
    if (mounted &&
        ok == true &&
        (pos.text.trim().isNotEmpty || tag.text.trim().isNotEmpty)) {
      await ref
          .read(databaseProvider)
          .batchAnnotate(
            items.map((e) => e.word.id).toList(),
            partOfSpeech: pos.text.trim().isEmpty ? null : pos.text.trim(),
            tag: tag.text.trim().isEmpty ? null : tag.text.trim(),
          );
      if (mounted) ref.invalidate(libraryWordsProvider);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      pos.dispose();
      tag.dispose();
    });
  }

  Future<void> _batch(List<LibraryWordEntry> items) async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      final runner = ref.read(aiTaskRunnerProvider);
      if (runner.isRunning) throw const AiException('busy');
      final words = items
          .where(
            (e) =>
                _selected.contains(e.word.id) &&
                isMissingMeaning(e.word.meaningZh),
          )
          .map((e) => e.word)
          .take(20)
          .toList();
      if (words.isEmpty) throw const AiException('batch_limit');
      final initial = await ref.read(aiContextProvider.future);
      if (!mounted) return;
      final context = await chooseAiContext(this.context, initial);
      if (!mounted || context == null) return;
      final id = await ref
          .read(aiRepositoryProvider)
          .createTask(words, context);
      if (!mounted) return;
      setState(() => _selected.removeAll(words.map((w) => w.id)));
      await this.context.push('/ai/tasks/$id');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final words = ref.watch(libraryWordsProvider),
        filter = ref.watch(libraryFilterProvider);
    final items = words.valueOrNull ?? [],
        selectable = items
            .where((e) => isMissingMeaning(e.word.meaningZh))
            .toList();
    final visibleSelected = selectable
        .where((e) => _selected.contains(e.word.id))
        .length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('统一词库'),
        actions: [
          IconButton(
            tooltip: '本机 AI 任务',
            onPressed: () => context.push('/ai/tasks'),
            icon: const Icon(Icons.auto_awesome),
          ),
          IconButton(
            tooltip: '录入新单词',
            onPressed: () => _edit(),
            icon: const Icon(Icons.add_circle_outline),
          ),
          PopupMenuButton<String>(
            tooltip: '词库操作',
            onSelected: (value) {
              if (value == 'import') context.push('/import');
              if (value == 'annotate') _annotate(items);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'import', child: Text('导入 Excel 词库')),
              PopupMenuItem(value: 'annotate', child: Text('批量标记当前结果')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('录入单词'),
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                child: Column(
                  children: [
                    const Text('所有来源已合并 · 英韩无中文词也进入统一学习'),
                    FilledButton.icon(
                      onPressed: () async {
                        await showSessionSheet(
                          context,
                          filter: filter == LibraryFilter.missingMeaning
                              ? LibraryFilter.all
                              : filter,
                        );
                        if (context.mounted) context.go('/study');
                      },
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('学习当前范围'),
                    ),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final tag in const ['工业术语', '物流', '邮件', '日常'])
                          ActionChip(
                            label: Text(tag),
                            onPressed: () async {
                              await showSessionSheet(context, tag: tag);
                              if (context.mounted) context.go('/study');
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      onChanged: (v) =>
                          ref.read(librarySearchProvider.notifier).state = v,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: '搜索单词、释义、词性或场景标签',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final entry in const [
                          (LibraryFilter.all, '全部'),
                          (LibraryFilter.favorites, '收藏'),
                          (LibraryFilter.wrong, '错词本'),
                          (LibraryFilter.missingMeaning, '待补中文'),
                        ])
                          ChoiceChip(
                            label: Text(entry.$2),
                            selected: filter == entry.$1,
                            onSelected: (_) {
                              ref.read(libraryFilterProvider.notifier).state =
                                  entry.$1;
                              setState(_selected.clear);
                            },
                          ),
                      ],
                    ),
                    if (selectable.isNotEmpty || _selected.isNotEmpty) ...[
                      const Divider(),
                      Text('已选 $visibleSelected 个待补中文词 · 本批最多 20 条'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          TextButton(
                            onPressed: () => setState(
                              () => _selected.addAll(
                                selectable.map((e) => e.word.id),
                              ),
                            ),
                            child: const Text('选择当前结果'),
                          ),
                          TextButton(
                            onPressed: () => setState(_selected.clear),
                            child: const Text('清除选择'),
                          ),
                          FilledButton(
                            onPressed: visibleSelected == 0 || _creating
                                ? null
                                : () => _batch(items),
                            child: Text(
                              visibleSelected > 20
                                  ? 'AI 批量补中文（前 20 条）'
                                  : 'AI 批量补中文',
                            ),
                          ),
                        ],
                      ),
                      if (visibleSelected > 20)
                        const Text('本批建成后保留剩余选择，可继续下一批。'),
                    ],
                    TextButton(
                      onPressed: () => context.push('/ai/tasks'),
                      child: const Text('查看任务进度、未完成任务与结果审核'),
                    ),
                  ],
                ),
              ),
            ),
            ...words.when(
              loading: () => [
                const SliverToBoxAdapter(
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
              error: (e, _) => [SliverToBoxAdapter(child: Text('读取词库失败：$e'))],
              data: (items) => items.isEmpty
                  ? [
                      SliverToBoxAdapter(
                        child: Center(
                          child: TextButton(
                            onPressed: () => _edit(),
                            child: const Text('没有找到单词，录入一个单词'),
                          ),
                        ),
                      ),
                    ]
                  : [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(14, 6, 14, 96),
                        sliver: SliverList.builder(
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index],
                                missing = isMissingMeaning(item.word.meaningZh);
                            return Card(
                              child: ListTile(
                                onTap: () => showWordDetail(context, item.word),
                                leading: missing
                                    ? Checkbox(
                                        value: _selected.contains(item.word.id),
                                        onChanged: (v) => setState(() {
                                          if (v == true) {
                                            _selected.add(item.word.id);
                                          } else {
                                            _selected.remove(item.word.id);
                                          }
                                        }),
                                      )
                                    : null,
                                title: Text(item.word.korean),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.word.meaningZh),
                                    Text(
                                      item.word.partOfSpeech?.isNotEmpty == true
                                          ? item.word.partOfSpeech!
                                          : '未标注词性',
                                    ),
                                    if (item.word.tags?.isNotEmpty == true)
                                      Text(item.word.tags!),
                                    if (item.wrongCount > 0)
                                      Text('错词 ×${item.wrongCount}'),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: item.isFavorite ? '取消收藏' : '收藏',
                                      icon: Icon(
                                        item.isFavorite
                                            ? Icons.star
                                            : Icons.star_border,
                                      ),
                                      onPressed: () async {
                                        await ref
                                            .read(databaseProvider)
                                            .setFavorite(
                                              item.word.id,
                                              !item.isFavorite,
                                            );
                                        if (mounted) {
                                          ref.invalidate(libraryWordsProvider);
                                        }
                                      },
                                    ),
                                    PopupMenuButton<String>(
                                      tooltip: '更多操作',
                                      onSelected: (v) {
                                        if (v == 'edit') {
                                          _edit(word: item.word);
                                        } else {
                                          _delete(item);
                                        }
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Text('编辑 / 标记词性'),
                                        ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Text('删除'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}

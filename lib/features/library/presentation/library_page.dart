import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../study/domain/providers.dart';
import '../../study/presentation/study_controller.dart';
import 'word_editor_sheet.dart';
import '../domain/providers.dart';
import '../../statistics/domain/providers.dart';

class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, {Word? word}) async {
    final saved = await showWordEditor(context, word: word);
    if (saved != true) return;
    ref.invalidate(libraryWordsProvider);
    ref.invalidate(homeCountsProvider);
    ref.invalidate(dailyPlanProgressProvider);
      ref.invalidate(studyRoundProgressProvider);
    ref.invalidate(studyControllerProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(word == null ? '单词已加入词库' : '词条已更新')),
      );
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    LibraryWordEntry item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除词条？'),
        content: Text('“${item.word.korean}”的复习记录和学习状态也会被删除，此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(databaseProvider).deleteWord(item.word.id);
      ref.invalidate(libraryWordsProvider);
      ref.invalidate(homeCountsProvider);
      ref.invalidate(dailyPlanProgressProvider);
      ref.invalidate(studyRoundProgressProvider);
      ref.invalidate(recentStatisticsProvider);
      ref.invalidate(studyControllerProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('词条已删除')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败：$error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = ref.watch(libraryWordsProvider);
    final filter = ref.watch(libraryFilterProvider);
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的词库'),
        actions: [
          IconButton(
            tooltip: '导入 Excel 词库',
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: () => context.push('/import'),
          ),
          IconButton(
            tooltip: '录入新单词',
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: () => _edit(context, ref),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('录入单词'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
              child: TextField(
                onChanged: (value) =>
                    ref.read(librarySearchProvider.notifier).state = value,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: '搜索韩语、中文或原形',
                ),
              ),
            ),
            SizedBox(
              height: 55,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                scrollDirection: Axis.horizontal,
                children: [
                  for (final entry in const [
                    (LibraryFilter.all, '全部'),
                    (LibraryFilter.favorites, '收藏'),
                    (LibraryFilter.wrong, '错词本'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(entry.$2),
                        selected: filter == entry.$1,
                        onSelected: (_) =>
                            ref.read(libraryFilterProvider.notifier).state = entry.$1,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: words.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(child: Text('读取词库失败：$error')),
                data: (items) => items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search_off_rounded,
                                size: 54, color: colors.onSurfaceVariant),
                            const SizedBox(height: 12),
                            const Text('没有找到单词'),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () => _edit(context, ref),
                              icon: const Icon(Icons.add),
                              label: const Text('录入一个单词'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 6, 14, 96),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final part = item.word.partOfSpeech?.trim();
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              contentPadding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
                              title: Text(
                                item.word.korean,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 3),
                                  Text(item.word.meaningZh),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        part == null || part.isEmpty ? '未标注词性' : part,
                                        style: TextStyle(
                                          color: colors.primary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (item.wrongCount > 0)
                                        Text(
                                          '错词 ×${item.wrongCount}',
                                          style: TextStyle(
                                            color: colors.error,
                                            fontSize: 12,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: item.isFavorite ? '取消收藏' : '收藏',
                                    icon: Icon(
                                      item.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                                      color: item.isFavorite ? Colors.amber.shade700 : null,
                                    ),
                                    onPressed: () async {
                                      await ref.read(databaseProvider)
                                          .setFavorite(item.word.id, !item.isFavorite);
                                      ref.invalidate(libraryWordsProvider);
                                    },
                                  ),
                                  PopupMenuButton<String>(
                                    tooltip: '更多操作',
                                    onSelected: (action) {
                                      if (action == 'edit') {
                                        _edit(context, ref, word: item.word);
                                      } else {
                                        _delete(context, ref, item);
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(value: 'edit', child: Text('编辑 / 标记词性')),
                                      PopupMenuItem(value: 'delete', child: Text('删除')),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

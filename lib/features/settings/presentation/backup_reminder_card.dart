import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../study/domain/providers.dart';
import '../domain/backup_status.dart';

/// An inline reminder, never a dialog over an active learning question.
class BackupReminderCard extends ConsumerStatefulWidget {
  const BackupReminderCard({super.key});
  @override
  ConsumerState<BackupReminderCard> createState() => _BackupReminderCardState();
}

class _BackupReminderCardState extends ConsumerState<BackupReminderCard> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final status = ref.watch(backupStatusProvider).valueOrNull;
    final counts = ref.watch(homeCountsProvider).valueOrNull;
    if (status == null ||
        counts == null ||
        (counts.newWords + counts.completed + counts.due == 0) ||
        !status.isDue(DateTime.now())) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('给学习进度留一份备份', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text('${status.lastExportLabel}。建议每周导出一次，保存到“文件”。'),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () => context.go('/settings?backup=1'),
                  icon: const Icon(Icons.save_alt),
                  label: const Text('去备份'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          try {
                            await ref
                                .read(databaseProvider)
                                .saveSetting(
                                  'backup_snoozed_until',
                                  DateTime.now()
                                      .toUtc()
                                      .add(const Duration(days: 3))
                                      .toIso8601String(),
                                );
                            if (mounted) ref.invalidate(backupStatusProvider);
                          } catch (_) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('未能保存提醒设置，请重试。')),
                              );
                            }
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                  child: const Text('3 天后提醒'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

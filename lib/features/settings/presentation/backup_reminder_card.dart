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
            Text('${status.lastExportLabel}。建议每周把 JSON 存到「文件」或 iCloud Drive。这是手动选择的位置，不会自动同步。'),
            const SizedBox(height: 6),
            const Text('用免费 Apple ID 侧载时，证书大约 7 天失效。请用同一个 Bundle ID 覆盖安装，不要先删除 App，否则词库和学习记录会丢失。'),
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

/// Shown on iPhone until dismissed. Other platforms do not need the sideload warning.
class IosSideloadHint extends ConsumerWidget {
  const IosSideloadHint({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (Theme.of(context).platform != TargetPlatform.iOS) {
      return const SizedBox.shrink();
    }
    final dismissed = ref.watch(sideloadHintProvider);
    if (dismissed.valueOrNull != false) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('把进度留在这台 iPhone 上', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text('免费证书大约 7 天后 App 会打不开。到期前用同一个 Bundle ID 覆盖安装，不要先删除「韩语记忆」。'),
            const SizedBox(height: 6),
            const Text('词库在本机。换机或重装前，到设置里把 JSON 备份存进「文件」或 iCloud Drive。这不是自动同步。'),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () async {
                  await ref.read(databaseProvider).saveSetting('sideload_hint_dismissed', 'true');
                  ref.invalidate(sideloadHintProvider);
                },
                child: const Text('知道了'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

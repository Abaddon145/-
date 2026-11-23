import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../study/domain/providers.dart';

class ReviewReminderTile extends ConsumerWidget {
  const ReviewReminderTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.notifications_outlined),
      title: const Text('每日复习提醒'),
      subtitle: const Text('记住提醒时间。关掉的主屏幕应用还不能自己响铃。'),
      onTap: () => _edit(context, ref),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    var enabled = (await db.loadSetting('reminder_enabled')) == 'true';
    final stored = await db.loadSetting('reminder_time') ?? '20:00';
    final parts = stored.split(':');
    var time = TimeOfDay(
      hour: int.tryParse(parts.first) ?? 20,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
    if (!context.mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('每日复习提醒'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'iPhone 装到主屏幕后，页面关掉就不会自己响。后台推送需要在代理上配置 VAPID 密钥，目前没有这份密钥，所以这里只记住你想提醒的时间，还不会到点响铃。',
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('记住这个时间'),
                value: enabled,
                onChanged: (value) => setLocal(() => enabled = value),
              ),
              TextButton(
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: time,
                  );
                  if (picked != null) setLocal(() => time = picked);
                },
                child: Text(
                  '每天 ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final clock =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    await db.saveSetting('reminder_enabled', enabled ? 'true' : 'false');
    await db.saveSetting('reminder_time', clock);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(enabled ? '已记住每天 $clock 提醒' : '已关闭复习提醒')),
      );
    }
  }
}

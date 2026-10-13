import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'cloud_sync_controller.dart';

class CloudSyncShortcut extends ConsumerWidget {
  const CloudSyncShortcut({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cloudSyncProvider);
    final colors = Theme.of(context).colorScheme;
    final attention = state.failed || state.needsChoice || state.pendingLocal || state.cloudChanged;
    final icon = state.userId == null ? Icons.cloud_outlined
        : state.failed ? Icons.cloud_off_outlined
        : state.cloudChanged || state.needsChoice ? Icons.cloud_download_outlined
        : state.busy || state.pendingLocal ? Icons.cloud_sync_outlined
        : Icons.cloud_done_outlined;
    return Card(child: ListTile(
      leading: Icon(icon, color: attention ? colors.tertiary : colors.primary),
      title: Text(state.label),
      subtitle: Text(state.userId == null ? '登录后可在其他设备接续学习'
          : state.pendingLocal ? '换设备前，先确认新记录已保存到云端'
          : state.cloudChanged || state.needsChoice ? '打开云同步，选择要接续的进度'
          : state.failed ? '本机记录已保留，点这里重试'
          : '词库、学习记录和打卡同步状态'),
      trailing: state.busy
          ? const SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.chevron_right),
      onTap: () => context.push('/settings/cloud'),
    ));
  }
}

String displaySyncTime(String? value) {
  final time = DateTime.tryParse(value ?? '')?.toLocal();
  if (time == null) return '尚无记录';
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${time.year}-${pad(time.month)}-${pad(time.day)} ${pad(time.hour)}:${pad(time.minute)}';
}

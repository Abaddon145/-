import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/appearance_settings.dart';
import '../../library/domain/providers.dart';
import '../../statistics/domain/providers.dart';
import '../../study/domain/providers.dart';
import '../../study/presentation/study_controller.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _busy = false;

  Future<void> _backup() async {
    setState(() => _busy = true);
    try {
      final data = await ref.read(databaseProvider).createBackupSnapshot();
      final bytes = Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(data)),
      );
      final saved = await FilePicker.saveFile(
        fileName: 'korean-memo-backup.json',
        bytes: bytes,
        mimeType: 'application/json',
      );
      if (saved != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('备份文件已导出')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('备份失败：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
        throw const FormatException('备份文件为空或超过 20 MB');
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('备份文件格式无效');
      }
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('恢复备份？'),
          content: const Text('恢复会替换此设备上的整个词库、学习进度和设置。建议先导出当前备份。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('替换并恢复'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      setState(() => _busy = true);
      await ref.read(databaseProvider).restoreBackupSnapshot(decoded);
      ref.invalidate(appearanceProvider);
      ref.invalidate(homeCountsProvider);
      ref.invalidate(studyControllerProvider);
      ref.invalidate(dailyPlanSettingsProvider);
      ref.invalidate(dailyPlanProgressProvider);
      ref.invalidate(studyRoundProgressProvider);
      ref.invalidate(libraryWordsProvider);
      ref.invalidate(recentStatisticsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('学习进度已恢复')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('恢复失败：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appearance = ref.watch(appearanceProvider).valueOrNull;
    final style = AppTheme.preset(appearance?.styleId ?? 'porcelain');
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 32),
          children: [
            Text('为自己定制每一天', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text('把学习节奏与视觉风格调整到最舒服的状态。',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 24),
            Text('学习偏好', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Card(
              child: Column(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
                    leading: _SettingIcon(Icons.palette_outlined, colors.primaryContainer),
                    title: const Text('外观风格'),
                    subtitle: Text('${style.name} · 可上传自己的背景'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/settings/appearance'),
                  ),
                  Divider(height: 1, indent: 72, color: colors.outlineVariant),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
                    leading: _SettingIcon(Icons.today_outlined, colors.secondaryContainer),
                    title: const Text('每日学习计划'),
                    subtitle: const Text('新词目标与复习上限'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/settings/daily-plan'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('数据管理', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Card(
              child: Column(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
                    leading: _SettingIcon(Icons.file_download_outlined, colors.tertiaryContainer),
                    title: const Text('备份学习进度'),
                    subtitle: const Text('包含词库、收藏、设置和背景'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _busy ? null : _backup,
                  ),
                  Divider(height: 1, indent: 72, color: colors.outlineVariant),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
                    leading: _SettingIcon(Icons.restore_rounded, colors.surfaceContainerHighest),
                    title: const Text('恢复学习进度'),
                    subtitle: const Text('从备份文件恢复本机数据'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _busy ? null : _restore,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Center(child: Text('KoreanMemo · v0.2.0')),
            if (_busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingIcon extends StatelessWidget {
  const _SettingIcon(this.icon, this.background);

  final IconData icon;
  final Color background;

  @override
  Widget build(BuildContext context) => CircleAvatar(
        backgroundColor: background,
        child: Icon(icon, color: Theme.of(context).colorScheme.onSurface),
      );
}

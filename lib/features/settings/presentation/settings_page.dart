import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/reading_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/appearance_settings.dart';
import '../../library/domain/providers.dart';
import '../../statistics/domain/providers.dart';
import '../../study/domain/providers.dart';
import '../../study/presentation/study_controller.dart';
import '../../../core/app_version.dart';
import '../../ai/domain/ai_providers.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _busy = false;
  bool _includeAi = false;
  late Future<String?> _lastBackup;
  @override
  void initState() {
    super.initState();
    _lastBackup = ref.read(databaseProvider).loadSetting('last_backup_at');
  }

  void _refreshData() {
    ref.invalidate(appearanceProvider);
    ref.invalidate(readingProvider);
    ref.invalidate(checkinsProvider);
    ref.invalidate(sessionOptionsProvider);
    ref.invalidate(sessionProgressProvider);
    ref.invalidate(homeCountsProvider);
    ref.invalidate(studyBookCountsProvider);
    ref.invalidate(wordBooksProvider);
    ref.invalidate(studyControllerProvider);
    ref.invalidate(dailyPlanSettingsProvider);
    ref.invalidate(dailyPlanProgressProvider);
    ref.invalidate(studyRoundProgressProvider);
    ref.invalidate(libraryWordsProvider);
    ref.invalidate(recentStatisticsProvider);
    ref.invalidate(aiTasksProvider);
    ref.invalidate(aiAddressProvider);
    ref.invalidate(aiContextProvider);
    ref.invalidate(aiModelProvider);
    ref.invalidate(aiConnectionModeProvider);
    ref.read(aiCredentialProvider.notifier).state = '';
  }

  Future<void> _undoRestore() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('撤销最近一次恢复？'),
        content: const Text('将用恢复前保留的本机快照替换当前数据。建议先导出当前备份。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('恢复到之前'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(aiTaskRunnerProvider).cancelAll();
      final restored = await ref
          .read(databaseProvider)
          .recoverPreviousRestore();
      if (!mounted) return;
      if (restored) _refreshData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(restored ? '已恢复到上一次快照' : '没有可恢复的快照')),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('恢复未完成，请检查备份文件后重试。')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backup() async {
    setState(() => _busy = true);
    try {
      final data = await ref
          .read(databaseProvider)
          .createBackupSnapshot(includeAi: _includeAi);
      final bytes = Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(data)),
      );
      final saved = await FilePicker.saveFile(
        fileName: 'korean-memo-backup.json',
        bytes: bytes,
        mimeType: 'application/json',
      );
      if (saved != null) {
        await ref
            .read(databaseProvider)
            .saveSetting(
              'last_backup_at',
              DateTime.now().toUtc().toIso8601String(),
            );
        if (mounted) {
          setState(
            () => _lastBackup = ref
                .read(databaseProvider)
                .loadSetting('last_backup_at'),
          );
        }
      }
      if (saved != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('备份文件已导出')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('备份失败：$error')));
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
      if (confirmed != true || !mounted) return;
      setState(() => _busy = true);
      await ref.read(aiTaskRunnerProvider).cancelAll();
      await ref.read(databaseProvider).restoreBackupSnapshot(decoded);
      if (!mounted) return;
      _refreshData();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('学习进度已恢复')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('恢复失败：$error')));
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
    final configured = ref.watch(aiApiKeyProvider).isNotEmpty;
    Widget tile(
      IconData icon,
      String title,
      String subtitle,
      VoidCallback? onTap,
    ) => ListTile(
      leading: Icon(icon, color: colors.primary),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: _busy ? null : onTap,
    );
    Widget group(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Column(children: children),
          ),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Card(
              color: colors.primaryContainer,
              margin: const EdgeInsets.only(bottom: 24),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.devices_rounded,
                      color: colors.onPrimaryContainer,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '你的学习，保存在本机',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    const Text('无需账户。换设备时，用备份文件带走词库与进度。'),
                  ],
                ),
              ),
            ),
            group('AI 学习助手', [
              tile(
                Icons.auto_awesome_rounded,
                'AI 学习助手设置',
                configured
                    ? 'DeepSeek 密钥已保存在此设备'
                    : '输入 DeepSeek API Key，开始使用',
                () => context.push('/settings/ai'),
              ),
              tile(
                Icons.fact_check_outlined,
                '本机 AI 任务',
                '查看进度、继续未完成任务与审核结果',
                () => context.push('/ai/tasks'),
              ),
            ]),
            group('学习与外观', [
              tile(
                Icons.today_outlined,
                '每日学习计划',
                '调整新词目标与复习上限',
                () => context.push('/settings/daily-plan'),
              ),
              tile(
                Icons.palette_outlined,
                '外观风格',
                '${style.name} · 六套主题与自定义背景',
                () => context.push('/settings/appearance'),
              ),
              tile(
                Icons.text_fields_rounded,
                '阅读、发音与背景调整',
                '字体、语速与专注模式',
                () => context.push('/settings/reading'),
              ),
              tile(
                Icons.calendar_month_outlined,
                '学习打卡与日历',
                '查看自己的学习节奏',
                () => context.push('/checkin'),
              ),
            ]),
            group('文件备份与迁移', [
              FutureBuilder<String?>(
                future: _lastBackup,
                builder: (context, snapshot) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      DateTime.tryParse(snapshot.data ?? '') == null
                          ? '还没有导出备份，建议定期保存一份。'
                          : '上次备份：${DateTime.parse(snapshot.data!).toLocal().toIso8601String().substring(0, 10)}',
                    ),
                  ),
                ),
              ),
              SwitchListTile(
                title: const Text('文件备份包含 AI 数据'),
                subtitle: const Text('包含建议与任务，不包含 API Key'),
                value: _includeAi,
                onChanged: _busy ? null : (v) => setState(() => _includeAi = v),
              ),
              tile(
                Icons.file_download_outlined,
                '备份学习进度',
                '导出词库、学习记录、收藏和设置',
                _backup,
              ),
              tile(
                Icons.restore_rounded,
                '恢复学习进度',
                '从 JSON 文件恢复；会替换本机数据',
                _restore,
              ),
              tile(
                Icons.undo_rounded,
                '撤销最近一次恢复',
                '返回恢复前保留的一次本机快照',
                _undoRestore,
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Text('将备份保存到“文件”或 iCloud Drive，即可在另一台设备导入。'),
              ),
            ]),
            TextButton.icon(
              onPressed: () => launchUrl(
                Uri.parse('https://abaddon145.github.io/-/guide.html'),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('查看配图使用指南'),
            ),
            TextButton.icon(
              onPressed: () => launchUrl(
                Uri.parse('https://github.com/Abaddon145/-/releases'),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_new),
              label: const Text('查看更新记录'),
            ),
            const Center(child: Text('KoreanMemo · v$appVersion')),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/database/app_database.dart';
import '../../study/domain/providers.dart';
import '../../../core/theme/app_motion.dart';
import '../../settings/presentation/backup_reminder_card.dart';
import '../../settings/domain/backup_status.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(homeCountsProvider);
    final seed = ref.watch(bundledWordSeedProvider);
    final plan = ref.watch(dailyPlanProgressProvider);
    final colors = Theme.of(context).colorScheme;
    void start() {
      ref.read(sessionOptionsProvider.notifier).daily();
      context.go('/study');
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('KoreanMemo'),
        actions: [
          IconButton(
            tooltip: 'AI 设置',
            onPressed: () => context.push('/settings/ai'),
            icon: const Icon(Icons.auto_awesome_outlined),
          ),
          IconButton(
            tooltip: '每日学习计划',
            onPressed: () => context.push('/settings/daily-plan'),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(homeCountsProvider);
            ref.invalidate(backupStatusProvider);
            ref.invalidate(dailyPlanProgressProvider);
            await ref.read(homeCountsProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              Text(
                '每天，让韩语熟悉一点',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '从今天的计划开始，按自己的节奏学习。',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              plan.when(
                data: (p) => _TodayCard(
                  progress: p,
                  ready: seed.hasValue,
                  onStart: start,
                  onPlan: () => context.push('/settings/daily-plan'),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => FilledButton(
                  onPressed: seed.hasValue ? start : null,
                  child: const Text('开始今天的学习'),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: Icon(
                    Icons.local_fire_department_outlined,
                    color: colors.primary,
                  ),
                  title: ref
                      .watch(checkinsProvider)
                      .when(
                        data: (c) =>
                            Text('连续 ${c.streak} 天 · 累计打卡 ${c.days.length} 天'),
                        loading: () => const Text('学习打卡'),
                        error: (_, _) => const Text('学习打卡'),
                      ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/checkin'),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Text('学习概览', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  TextButton(
                    onPressed: () => context.go('/statistics'),
                    child: const Text('查看统计'),
                  ),
                ],
              ),
              counts.when(
                data: (v) => Row(
                  children: [
                    Expanded(
                      child: _MetricCard('待复习', v.due, Icons.history_rounded),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MetricCard(
                        '未学习',
                        v.newWords,
                        Icons.layers_outlined,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MetricCard(
                        '累计评分',
                        v.completed,
                        Icons.check_circle_outline,
                      ),
                    ),
                  ],
                ),
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => const Text('暂时无法读取统计，下拉可重试。'),
              ),
              const SizedBox(height: 24),
              const BackupReminderCard(),
              const SizedBox(height: 20),
              Text('常用入口', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              for (final entry in [
                (Icons.menu_book_outlined, '我的词库', '搜索、收藏与编辑单词', '/library'),
                (
                  Icons.auto_awesome_outlined,
                  'AI 学习助手',
                  '配置 DeepSeek API Key',
                  '/settings/ai',
                ),
                (
                  Icons.fact_check_outlined,
                  '本机 AI 任务',
                  '继续任务与审核生成结果',
                  '/ai/tasks',
                ),
                (
                  Icons.file_upload_outlined,
                  '导入 Excel 词库',
                  '把自己的单词带进来',
                  '/import',
                ),
              ])
                PressFeedback(
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: Icon(entry.$1, color: colors.primary),
                      title: Text(entry.$2),
                      subtitle: Text(entry.$3),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => entry.$4 == '/library'
                          ? context.go(entry.$4)
                          : context.push(entry.$4),
                    ),
                  ),
                ),
              if (seed.hasError)
                Text(
                  '内置词库未准备完成，请保持此页并重试。',
                  style: TextStyle(color: colors.error),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.progress,
    required this.ready,
    required this.onStart,
    required this.onPlan,
  });
  final DailyPlanProgress progress;
  final bool ready;
  final VoidCallback onStart, onPlan;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final started = progress.newWordsDone + progress.reviewsDone > 0;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.primaryContainer,
              Color.alphaBlend(
                colors.primary.withValues(alpha: .06),
                colors.surface,
              ),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '今日学习',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '调整今日计划',
                    onPressed: onPlan,
                    icon: const Icon(Icons.tune_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _PlanRow(
                '新词',
                progress.newWordsDone,
                progress.settings.newWordsPerDay,
              ),
              const SizedBox(height: 14),
              _PlanRow(
                '复习',
                progress.reviewsDone,
                progress.settings.reviewsPerDay,
              ),
              const SizedBox(height: 22),
              PressFeedback(
                child: FilledButton.icon(
                  onPressed: ready ? onStart : null,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    !ready
                        ? '正在准备词库…'
                        : started
                        ? '继续今日学习'
                        : '开始今天的学习',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text('完成目标后仍可继续新词、复习或混合练习。'),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow(this.label, this.done, this.target);
  final String label;
  final int done, target;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(children: [Text(label), const Spacer(), Text('$done / $target')]),
      const SizedBox(height: 6),
      SmoothProgress(
        value: target == 0 ? 1 : (done / target).clamp(0, 1).toDouble(),
      ),
    ],
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(this.label, this.value, this.icon);
  final String label;
  final int value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Column(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 8),
          Text(
            '$value',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    ),
  );
}

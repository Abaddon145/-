import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/database/app_database.dart';
import '../../study/domain/providers.dart';
import '../../../core/theme/app_motion.dart';
import '../../settings/presentation/backup_reminder_card.dart';
import 'web_storage_banner.dart';
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
      appBar: AppBar(title: const Text('词忆')),
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
                ref.watch(activeLanguageProvider) == 'en'
                    ? '每天，让英语熟悉一点'
                    : '每天，让韩语熟悉一点',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                ref.watch(activeLanguageProvider) == 'en'
                    ? '从今天的计划开始，按自己的节奏学英语。'
                    : '从今天的计划开始，按自己的节奏学习。',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'ko', label: Text('韩语')),
                  ButtonSegment(value: 'en', label: Text('英语')),
                ],
                selected: {ref.watch(activeLanguageProvider)},
                onSelectionChanged: (selected) {
                  ref
                      .read(activeLanguageProvider.notifier)
                      .select(selected.first);
                },
              ),
              const SizedBox(height: 20),
              plan.when(
                skipLoadingOnReload: true,
                skipLoadingOnRefresh: true,
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
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => context.push('/checkin'),
                  child: ref
                      .watch(checkinsProvider)
                      .when(
                        skipLoadingOnReload: true,
                        skipLoadingOnRefresh: true,
                        data: (c) => Text(
                          '连续 ${c.streak} 天 · 累计打卡 ${c.days.length} 天',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        loading: () => const Text('学习打卡'),
                        error: (_, _) => const Text('学习打卡'),
                      ),
                ),
              ),
              const SizedBox(height: 12),
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
                skipLoadingOnReload: true,
                skipLoadingOnRefresh: true,
                data: (v) => AnimatedSwitcher(
                  duration: AppMotion.duration(context, 180),
                  child: Card(
                    key: ValueKey(
                      '${ref.watch(activeLanguageProvider)}:${v.due}:${v.learningDue}:${v.newWords}',
                    ),
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: IntrinsicHeight(
                        child: Row(
                          children: [
                            _CountCell('待复习', v.due, emphasize: v.due > 0),
                            const VerticalDivider(),
                            _CountCell('学习中', v.learningDue, emphasize: false),
                            const VerticalDivider(),
                            _CountCell('未学习', v.newWords, emphasize: false),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => const Text('暂时无法读取统计，下拉可重试。'),
              ),
              const SizedBox(height: 12),
              const WebStorageBanner(),
              const SizedBox(height: 12),
              const BackupReminderCard(),
              const SizedBox(height: 20),
              Text('常用入口', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(
                        Icons.fact_check_outlined,
                        color: colors.primary,
                      ),
                      title: const Text('本机 AI 任务'),
                      subtitle: const Text('继续任务与审核生成结果'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.push('/ai/tasks'),
                    ),
                    const Divider(indent: 56, height: 1),
                    ListTile(
                      leading: Icon(
                        Icons.file_upload_outlined,
                        color: colors.primary,
                      ),
                      title: Text(
                        ref.watch(activeLanguageProvider) == 'en'
                            ? '导入英语词表'
                            : '导入 Excel 词库',
                      ),
                      subtitle: Text(
                        ref.watch(activeLanguageProvider) == 'en'
                            ? 'CSV 或 TSV，只写入英语'
                            : '把自己的单词带进来',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.push('/import'),
                    ),
                  ],
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
    final base = Theme.of(context).brightness == Brightness.dark
        ? colors.surfaceContainerHigh
        : colors.surfaceContainerLowest;
    final tint = Color.alphaBlend(colors.primary.withValues(alpha: .14), base);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [tint, base],
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Row(children: [Text(label), const Spacer(), Text('$done / $target')]),
        const SizedBox(height: 6),
        Theme(
          data: theme.copyWith(
            progressIndicatorTheme: theme.progressIndicatorTheme.copyWith(
              linearTrackColor: theme.colorScheme.primary.withValues(
                alpha: .24,
              ),
            ),
          ),
          child: SmoothProgress(
            value: target == 0 ? 1 : (done / target).clamp(0, 1).toDouble(),
          ),
        ),
      ],
    );
  }
}

class _CountCell extends StatelessWidget {
  const _CountCell(this.label, this.value, {required this.emphasize});
  final String label;
  final int value;
  final bool emphasize;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: emphasize ? scheme.primary : scheme.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

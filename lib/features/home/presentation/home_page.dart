import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../study/domain/providers.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(homeCountsProvider);
    final seed = ref.watch(bundledWordSeedProvider);
    final plan = ref.watch(dailyPlanProgressProvider);
    final colors = Theme.of(context).colorScheme;
    final ready = seed.hasValue;
    return Scaffold(
      appBar: AppBar(
        title: const Text('KoreanMemo'),
        actions: [
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
            ref.invalidate(dailyPlanProgressProvider);
            await ref.read(homeCountsProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Text('안녕하세요', style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 4),
              Text('每天一点点，让韩语更熟悉。',
                  style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 24),
              Card(
                color: colors.primaryContainer.withValues(alpha: 0.88),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.auto_stories_rounded,
                          color: colors.onPrimaryContainer, size: 30),
                      const SizedBox(height: 16),
                      Text(
                        '今天，继续向前一步',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: colors.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '短短几分钟，也能留下新的记忆。',
                        style: TextStyle(color: colors.onPrimaryContainer),
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: ready ? () {
                          ref.read(studyBookProvider.notifier).state = null;
                          context.go('/study');
                        } : null,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(ready ? '开始今天的学习' : '正在准备词库…'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
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
              const SizedBox(height: 8),
              counts.when(
                data: (value) => Row(
                  children: [
                    Expanded(child: _MetricCard('待复习', value.due, Icons.history_rounded)),
                    const SizedBox(width: 8),
                    Expanded(child: _MetricCard('未学习', value.newWords, Icons.layers_outlined)),
                    const SizedBox(width: 8),
                    Expanded(child: _MetricCard('累计评分', value.completed, Icons.check_circle_outline)),
                  ],
                ),
                loading: () => const LinearProgressIndicator(),
                error: (error, _) => Text('读取学习数据失败：$error'),
              ),
              const SizedBox(height: 18),
              plan.when(
                data: (value) => _DailyPlanCard(
                  progress: value,
                  onTap: () => context.push('/settings/daily-plan'),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (error, _) => Text('读取每日计划失败：$error'),
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: () => context.go('/library'),
                icon: const Icon(Icons.menu_book_outlined),
                label: const Text('打开我的词库'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => context.push('/import'),
                icon: const Icon(Icons.file_upload_outlined),
                label: const Text('导入 Excel 词库'),
              ),
              if (seed.hasError)
                Text(
                  '内置词库导入失败：${seed.error}',
                  style: TextStyle(color: colors.error),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(this.label, this.value, this.icon);

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 15),
        child: Column(
          children: [
            Icon(icon, color: colors.primary, size: 22),
            const SizedBox(height: 8),
            Text('$value', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 2),
            Text(label, style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _DailyPlanCard extends StatelessWidget {
  const _DailyPlanCard({required this.progress, required this.onTap});

  final DailyPlanProgress progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final newProgress =
        (progress.newWordsDone / progress.settings.newWordsPerDay).clamp(0, 1);
    final reviewProgress =
        (progress.reviewsDone / progress.settings.reviewsPerDay).clamp(0, 1);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.today_rounded),
                  const SizedBox(width: 10),
                  Text('今日计划', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              const SizedBox(height: 18),
              _PlanRow('新词', progress.newWordsDone,
                  progress.settings.newWordsPerDay, newProgress.toDouble()),
              const SizedBox(height: 14),
              _PlanRow('复习', progress.reviewsDone,
                  progress.settings.reviewsPerDay, reviewProgress.toDouble()),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow(this.label, this.done, this.target, this.progress);

  final String label;
  final int done;
  final int target;
  final double progress;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Row(
            children: [
              Text(label),
              const Spacer(),
              Text('$done / $target'),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: progress),
        ],
      );
}

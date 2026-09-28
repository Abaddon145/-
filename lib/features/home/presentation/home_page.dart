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
    final dailyPlan = ref.watch(dailyPlanProgressProvider);
    final wordsReady = seed.hasValue;
    return Scaffold(
      appBar: AppBar(
        title: const Text('KoreanMemo'),
        actions: [
          IconButton(
            tooltip: '每日学习计划',
            onPressed: () => context.push('/settings/daily-plan'),
            icon: const Icon(Icons.tune_rounded),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: () => ref.invalidate(homeCountsProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(homeCountsProvider.future),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('안녕하세요', style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 6),
              Text('今天继续积累一点。',
                  style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 28),
              counts.when(
                data: (value) => Row(
                  children: [
                    Expanded(
                      child: _MetricCard(label: '待复习', value: value.due),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MetricCard(label: '未学习', value: value.newWords),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MetricCard(label: '累计评分', value: value.completed),
                    ),
                  ],
                ),
                loading: () => const LinearProgressIndicator(),
                error: (error, _) => Text('读取学习数据失败：$error'),
              ),
              const SizedBox(height: 20),
              dailyPlan.when(
                data: (value) => _DailyPlanCard(
                  progress: value,
                  onTap: () => context.push('/settings/daily-plan'),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (error, _) => Text('读取每日计划失败：$error'),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: wordsReady ? () => context.push('/study') : null,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(wordsReady ? '开始学习' : '正在导入词库…'),
              ),
              if (seed.hasError) ...[
                const SizedBox(height: 12),
                Text(
                  '内置词库导入失败：${seed.error}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.push('/import'),
                icon: const Icon(Icons.table_view_rounded),
                label: const Text('导入 Excel 词库'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 18),
        child: Column(
          children: [
            Text('$value', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
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
    final newWordProgress =
        (progress.newWordsDone / progress.settings.newWordsPerDay).clamp(0, 1);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.today_rounded),
                  const SizedBox(width: 10),
                  Text(
                    '每日学习计划',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              const SizedBox(height: 14),
              LinearProgressIndicator(value: newWordProgress.toDouble()),
              const SizedBox(height: 10),
              Text(
                '新词 ${progress.newWordsDone}/'
                '${progress.settings.newWordsPerDay} · '
                '复习 ${progress.reviewsDone}/'
                '${progress.settings.reviewsPerDay}（上限）',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

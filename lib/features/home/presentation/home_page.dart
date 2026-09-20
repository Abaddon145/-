import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../study/domain/providers.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(homeCountsProvider);
    final seed = ref.watch(bundledWordSeedProvider);
    final wordsReady = seed.hasValue;
    return Scaffold(
      appBar: AppBar(
        title: const Text('KoreanMemo'),
        actions: [
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

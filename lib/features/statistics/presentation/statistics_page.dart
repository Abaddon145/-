import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/database/app_database.dart';
import '../../study/domain/providers.dart';
import '../domain/providers.dart';
import '../data/learning_report.dart';

class StatisticsPage extends ConsumerWidget {
  const StatisticsPage({super.key});
  Future<void> _export(BuildContext context, WidgetRef ref, bool csv) async {
    try {
      final db = ref.read(databaseProvider);
      final text = csv
          ? await LearningReport.csv(db, DateTime.now())
          : await LearningReport.weekly(db, DateTime.now());
      await FilePicker.saveFile(
        fileName: csv ? 'learning-report.csv' : 'learning-weekly.md',
        bytes: Uint8List.fromList(utf8.encode(text)),
        mimeType: csv ? 'text/csv' : 'text/markdown',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败：$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(recentStatisticsProvider);
    final objective = ref.watch(objectiveStatisticsProvider).valueOrNull ?? {};
    return Scaffold(
      appBar: AppBar(
        title: const Text('学习统计'),
        actions: [
          IconButton(
            tooltip: '刷新统计',
            onPressed: () {
              ref.invalidate(recentStatisticsProvider);
              ref.invalidate(monthStatisticsProvider);
              ref.invalidate(learningOverviewProvider);
              ref.invalidate(reviewForecastProvider);
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: '导出学习报告',
            onSelected: (v) => _export(context, ref, v == 'csv'),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'csv', child: Text('导出30天 CSV')),
              PopupMenuItem(value: 'weekly', child: Text('导出本周报告')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: stats.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('读取统计失败：$e')),
          data: (days) {
            final today = days.isEmpty ? null : days.last;
            final total = days.fold<int>(0, (n, r) => n + r.newWords + r.reviews);
            final correct = days.fold<int>(0, (n, r) => n + r.correct);
            final wrong = days.fold<int>(0, (n, r) => n + r.wrong);
            final mins = days.fold<int>(0, (n, r) => n + r.durationMs) ~/ 60000;
            final testTotal = days.fold<int>(0, (n, r) => n + (objective[dayKey(r.date)]?['total'] ?? 0));
            final testCorrect = days.fold<int>(0, (n, r) => n + (objective[dayKey(r.date)]?['correct'] ?? 0));
            final selfTotal = correct + wrong - testTotal;
            final selfCorrect = correct - testCorrect;
            final accuracy = selfTotal <= 0 ? 0 : (selfCorrect * 100 / selfTotal).round();
            final todayTest = objective[today == null ? '' : dayKey(today.date)] ?? {'total': 0, 'correct': 0};
            final todaySelfTotal = (today?.correct ?? 0) + (today?.wrong ?? 0) - todayTest['total']!;
            final todayAccuracy = todaySelfTotal <= 0
                ? 0
                : (((today?.correct ?? 0) - todayTest['correct']!) * 100 / todaySelfTotal).round();
            final todayMinutes = (today?.durationMs ?? 0) ~/ 60000;
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(recentStatisticsProvider);
                await ref.read(recentStatisticsProvider.future);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                children: [
                  Text('今日', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _StatTile('新词', '${today?.newWords ?? 0}')),
                      const SizedBox(width: 8),
                      Expanded(child: _StatTile('复习', '${today?.reviews ?? 0}')),
                      const SizedBox(width: 8),
                      Expanded(child: _StatTile('学习时长', '$todayMinutes 分钟')),
                      const SizedBox(width: 8),
                      Expanded(child: _StatTile('自评记忆率', '$todayAccuracy%')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('客观测试  ${todayTest['correct']}/${todayTest['total']}'),
                  const SizedBox(height: 8),
                  Text(
                    '自评记忆率只看翻卡时你选的「认识」和「简单」。客观测试是拼写、听写、填空和词形里判对的次数。两套数字分开，测试成绩不会改写自评。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  ref.watch(learningOverviewProvider).when(
                    data: (v) => Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text('已学不同单词 ${v['learned']} · 已标熟词 ${v['known']} · 暂停 ${v['suspended']}'),
                    ),
                    loading: () => const SizedBox(),
                    error: (_, _) => const SizedBox(),
                  ),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.calendar_month_rounded),
                      title: ref.watch(checkinsProvider).when(
                        data: (v) => Text('连续打卡 ${v.streak} 天 · 最长 ${v.longest} 天'),
                        loading: () => const Text('学习日历'),
                        error: (_, _) => const Text('学习日历'),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/checkin'),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '近 7 天 · $total 次 · 自评记忆率 $accuracy% · $mins 分钟',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text('客观测试：$testCorrect / $testTotal'),
                  for (final day in days)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${day.date.month}月${day.date.day}日'),
                      subtitle: Text('新词 ${day.newWords} · 复习 ${day.reviews}'),
                      trailing: Text('${day.correct} 认识 / ${day.wrong} 忘记'),
                    ),
                  const Divider(),
                  Text('近30天学习热力图', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  const Text('按周一到周日排列。点一天可以看当天次数，不必依赖长按提示。'),
                  const SizedBox(height: 8),
                  ref.watch(monthStatisticsProvider).when(
                    data: (rows) => _StudyHeatmap(rows: rows),
                    loading: () => const LinearProgressIndicator(),
                    error: (_, _) => const SizedBox(),
                  ),
                  const SizedBox(height: 18),
                  Text('未来7天到期复习', style: Theme.of(context).textTheme.titleMedium),
                  ref.watch(reviewForecastProvider).when(
                    data: (rows) => Column(
                      children: [
                        for (final row in rows)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('${row['day']}'),
                            trailing: Text('${row['count']} 个'),
                          ),
                      ],
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (_, _) => const SizedBox(),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      child: Column(
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class _StudyHeatmap extends StatefulWidget {
  const _StudyHeatmap({required this.rows});
  final List<DailyStatisticsSummary> rows;
  @override
  State<_StudyHeatmap> createState() => _StudyHeatmapState();
}

class _StudyHeatmapState extends State<_StudyHeatmap> {
  DailyStatisticsSummary? _selected;

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    if (rows.isEmpty) return const Text('最近 30 天还没有记录');
    final selected = _selected ?? rows.last;
    final colors = Theme.of(context).colorScheme;
    final leading = rows.first.date.weekday - 1;
    final cells = <DailyStatisticsSummary?>[
      for (var i = 0; i < leading; i++) null,
      ...rows,
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    final first = rows.first.date;
    final last = rows.last.date;
    final span = first.month == last.month ? '${first.month}月' : '${first.month}月 – ${last.month}月';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(span, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final label in const ['一', '二', '三', '四', '五', '六', '日'])
              Expanded(child: Center(child: Text(label))),
          ],
        ),
        const SizedBox(height: 4),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: cells.length,
          itemBuilder: (context, index) {
            final row = cells[index];
            if (row == null) return const SizedBox.shrink();
            final count = row.newWords + row.reviews;
            final active = selected.date == row.date;
            return Semantics(
              button: true,
              selected: active,
              label: '${row.date.month}月${row.date.day}日，$count 次学习',
              child: Material(
                color: count == 0
                    ? colors.surfaceContainerHighest
                    : colors.primary.withValues(alpha: (.28 + .72 * (count / 20).clamp(0, 1))),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: active ? colors.primary : Colors.transparent, width: 2),
                ),
                child: InkWell(
                  onTap: () => setState(() => _selected = row),
                  borderRadius: BorderRadius.circular(8),
                  child: Center(
                    child: FittedBox(
                      child: Text(
                        '${row.date.day}',
                        style: TextStyle(color: count == 0 ? colors.onSurfaceVariant : colors.onPrimary),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          '${selected.date.month}月${selected.date.day}日 · 新词 ${selected.newWords} · 复习 ${selected.reviews} · 认识 ${selected.correct} · 忘记 ${selected.wrong}',
        ),
      ],
    );
  }
}

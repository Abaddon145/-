import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/database/app_database.dart';
import '../../../core/theme/app_motion.dart';
import '../../study/domain/providers.dart';
import '../domain/providers.dart';
import '../data/learning_report.dart';
import 'language_comparison_card.dart';
import '../../atlas/domain/atlas_providers.dart';

class StatisticsPage extends ConsumerWidget {
  const StatisticsPage({super.key});
  Future<void> _export(BuildContext context, WidgetRef ref, bool csv) async {
    try {
      final db = ref.read(databaseProvider);
      final language = ref.read(activeLanguageProvider);
      final text = csv
          ? await LearningReport.csv(db, DateTime.now(), language)
          : await LearningReport.weekly(db, DateTime.now(), language);
      await FilePicker.saveFile(
        fileName: csv ? 'learning-report.csv' : 'learning-weekly.md',
        bytes: Uint8List.fromList(utf8.encode(text)),
        mimeType: csv ? 'text/csv' : 'text/markdown',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导出失败：$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(recentStatisticsProvider),
        colors = Theme.of(context).colorScheme;
    final scope = ref.watch(statisticsScopeProvider);
    final objective = ref.watch(objectiveStatisticsProvider).valueOrNull ?? {};
    final atlasStats = ref.watch(atlasStatsProvider).valueOrNull;
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
      body: stats.when(
        skipLoadingOnReload: true,
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('读取统计失败：$e')),
        data: (days) {
          final today = days.isEmpty ? null : days.last;
          final total = days.fold<int>(0, (n, r) => n + r.newWords + r.reviews);
          final correct = days.fold<int>(0, (n, r) => n + r.correct),
              wrong = days.fold<int>(0, (n, r) => n + r.wrong);
          final mins = days.fold<int>(0, (n, r) => n + r.durationMs) ~/ 60000;
          final testTotal = days.fold<int>(
            0,
            (n, r) => n + (objective[dayKey(r.date)]?['total'] ?? 0),
          );
          final testCorrect = days.fold<int>(
            0,
            (n, r) => n + (objective[dayKey(r.date)]?['correct'] ?? 0),
          );
          final selfTotal = correct + wrong - testTotal,
              selfCorrect = correct - testCorrect;
          final accuracy = selfTotal <= 0
              ? 0
              : (selfCorrect * 100 / selfTotal).round();
          final todayTest =
              objective[today == null ? '' : dayKey(today.date)] ??
              {'total': 0, 'correct': 0};
          final todaySelfTotal =
              (today?.correct ?? 0) + (today?.wrong ?? 0) - todayTest['total']!;
          final todayAccuracy = todaySelfTotal <= 0
              ? 0
              : (((today?.correct ?? 0) - todayTest['correct']!) *
                        100 /
                        todaySelfTotal)
                    .round();
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(recentStatisticsProvider);
              await ref.read(recentStatisticsProvider.future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(18),
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 'active', label: Text('当前')),
                      ButtonSegment(value: 'ko', label: Text('韩语')),
                      ButtonSegment(value: 'en', label: Text('英语')),
                      ButtonSegment(value: 'all', label: Text('全部')),
                    ],
                    selected: {scope},
                    onSelectionChanged: (value) =>
                        ref.read(statisticsScopeProvider.notifier).state =
                            value.first,
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '已掌握 ${atlasStats?.mastered ?? 0}（复习态且稳定度 ≥ 21 天） · 首次作答正确率 ${atlasStats?.firstAccuracy ?? 0}%',
                    ),
                  ),
                ),
                if (scope == 'all') ...[
                  const SizedBox(height: 12),
                  const LanguageComparisonCard(),
                ],
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '今日',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        _StatGrid(
                          cells: [
                            ('${today?.newWords ?? 0}', '新词'),
                            ('${today?.reviews ?? 0}', '复习'),
                            ('$todayAccuracy%', '自评记忆率'),
                            ('${(today?.durationMs ?? 0) ~/ 60000}', '学习分钟'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '客观测试  ${todayTest['correct']}/${todayTest['total']}',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
                ref
                    .watch(learningOverviewProvider)
                    .when(
                      data: (v) => Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Text(
                            '已学不同单词 ${v['learned']} · 已标熟词 ${v['known']} · 暂停 ${v['suspended']}',
                          ),
                        ),
                      ),
                      loading: () => const SizedBox(),
                      error: (_, _) => const SizedBox(),
                    ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.calendar_month_rounded),
                    title: ref
                        .watch(statisticsCheckinsProvider)
                        .when(
                          data: (v) =>
                              Text('连续打卡 ${v.streak} 天 · 最长 ${v.longest} 天'),
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
                const SizedBox(height: 12),
                SizedBox(height: 120, child: _WeekBars(days: days)),
                ExpansionTile(
                  title: const Text('查看明细'),
                  children: [
                    for (final day in days)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${day.date.month}月${day.date.day}日'),
                        subtitle: Text(
                          '新词 ${day.newWords} · 复习 ${day.reviews}',
                        ),
                        trailing: Text('${day.correct} 认识 / ${day.wrong} 忘记'),
                      ),
                  ],
                ),
                const Divider(),
                Text(
                  '近30天学习热力图',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                ref
                    .watch(monthStatisticsProvider)
                    .when(
                      data: (rows) => Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final row in rows)
                            Tooltip(
                              message:
                                  '${dayKey(row.date)} · ${row.newWords + row.reviews} 次',
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  color: row.newWords + row.reviews == 0
                                      ? colors.surfaceContainerHighest
                                      : colors.primary.withValues(
                                          alpha:
                                              (.2 +
                                              .8 *
                                                  ((row.newWords +
                                                              row.reviews) /
                                                          50)
                                                      .clamp(0, 1)),
                                        ),
                                ),
                                child: Center(
                                  child: Text(
                                    '${row.date.day}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      loading: () => const LinearProgressIndicator(),
                      error: (_, _) => const SizedBox(),
                    ),
                const SizedBox(height: 18),
                Text(
                  '未来7天到期复习',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                ref
                    .watch(reviewForecastProvider)
                    .when(
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
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.cells});
  final List<(String, String)> cells;
  @override
  Widget build(BuildContext context) {
    final label = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    final number = Theme.of(context).textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.4,
      children: [
        for (final cell in cells)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(cell.$1, style: number),
              Text(cell.$2, style: label),
            ],
          ),
      ],
    );
  }
}

class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.days});
  final List<DailyStatisticsSummary> days;
  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final quiet =
        days.isEmpty || days.every((day) => day.newWords + day.reviews == 0);
    final description = quiet
        ? '完成第一次学习后，这里会显示近 7 天的柱状图'
        : '近 7 天学习次数：${days.map((day) => '周${_weekdays[day.date.weekday - 1]} ${day.newWords + day.reviews}次').join('，')}';
    final maxValue = days.fold<int>(
      1,
      (max, day) => math.max(max, day.newWords + day.reviews),
    );
    return Semantics(
      label: description,
      child: ExcludeSemantics(
        child: quiet
            ? Center(
                child: Text(
                  '完成第一次学习后，这里会显示近 7 天的柱状图',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              )
            : Column(
                children: [
                  Expanded(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: AppMotion.duration(context, 300),
                      curve: Curves.easeOutCubic,
                      builder: (context, t, _) => CustomPaint(
                        painter: _WeekBarPainter(
                          days: days,
                          maxValue: maxValue,
                          progress: t,
                          primary: colors.primary,
                          again: colors.errorContainer,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (final day in days)
                        Expanded(
                          child: Text(
                            _weekdays[day.date.weekday - 1],
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

class _WeekBarPainter extends CustomPainter {
  _WeekBarPainter({
    required this.days,
    required this.maxValue,
    required this.progress,
    required this.primary,
    required this.again,
  });
  final List<DailyStatisticsSummary> days;
  final int maxValue;
  final double progress;
  final Color primary, again;
  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;
    final slot = size.width / days.length;
    final barWidth = slot * 0.55;
    for (var i = 0; i < days.length; i++) {
      final day = days[i];
      final total = day.newWords + day.reviews;
      final height = size.height * (total / maxValue) * progress;
      final left = slot * i + (slot - barWidth) / 2;
      final top = size.height - height;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, barWidth, height),
          const Radius.circular(6),
        ),
        Paint()..color = primary,
      );
      if (day.wrong > 0 && total > 0) {
        final wrongHeight = height * (day.wrong / total);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              left,
              size.height - wrongHeight,
              barWidth,
              wrongHeight,
            ),
            const Radius.circular(6),
          ),
          Paint()..color = again,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WeekBarPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.days != days;
}

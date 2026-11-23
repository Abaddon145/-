import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../data/language_comparison.dart';
import '../domain/providers.dart';

class LanguageComparisonCard extends ConsumerWidget {
  const LanguageComparisonCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    return ref
        .watch(languageComparisonProvider)
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Text('语言对比没有读出来：$error'),
          data: (data) {
            final ko = data.days['ko'] ?? const <DailyStatisticsSummary>[];
            final en = data.days['en'] ?? const <DailyStatisticsSummary>[];
            final koReviews = ko.fold<int>(0, (sum, day) => sum + day.reviews);
            final enReviews = en.fold<int>(0, (sum, day) => sum + day.reviews);
            final koMinutes =
                ko.fold<int>(0, (sum, day) => sum + day.durationMs) ~/ 60000;
            final enMinutes =
                en.fold<int>(0, (sum, day) => sum + day.durationMs) ~/ 60000;
            final quiet =
                koReviews + enReviews == 0 &&
                (data.mastery['ko']?.total ?? 0) +
                        (data.mastery['en']?.total ?? 0) ==
                    0;
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('语言对比', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 6),
                    Text(
                      '掌握程度按记忆间隔：新学不到 1 天，初识 1–7 天，熟悉 7–30 天，掌握 30 天以上。',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (quiet)
                      Text(
                        '学过韩语或英语之后，这里会并排显示两种语言。',
                        style: Theme.of(context).textTheme.bodyMedium,
                      )
                    else ...[
                      SizedBox(
                        height: 120,
                        child: _MasteryChart(
                          ko: data.mastery['ko']!,
                          en: data.mastery['en']!,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('韩语复习 $koReviews 次 · $koMinutes 分钟'),
                      Text('英语复习 $enReviews 次 · $enMinutes 分钟'),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 96,
                        child: _SplitWeek(ko: ko, en: en),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
  }
}

class _MasteryChart extends StatelessWidget {
  const _MasteryChart({required this.ko, required this.en});

  final MasteryCount ko;
  final MasteryCount en;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final labels = ['新学', '初识', '熟悉', '掌握'];
    final korean = [ko.fresh, ko.week, ko.month, ko.steady];
    final english = [en.fresh, en.week, en.month, en.steady];
    final maxValue = math.max(1, [...korean, ...english].reduce(math.max));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _Bar(
                        value: korean[i],
                        maxValue: maxValue,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 4),
                      _Bar(
                        value: english[i],
                        maxValue: maxValue,
                        color: colors.tertiary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(labels[i], style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
      ],
    );
  }
}

class _SplitWeek extends StatelessWidget {
  const _SplitWeek({required this.ko, required this.en});

  final List<DailyStatisticsSummary> ko;
  final List<DailyStatisticsSummary> en;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final count = math.max(ko.length, en.length);
    var maxValue = 1;
    for (var i = 0; i < count; i++) {
      maxValue = math.max(maxValue, i < ko.length ? ko[i].reviews : 0);
      maxValue = math.max(maxValue, i < en.length ? en[i].reviews : 0);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < count; i++)
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Bar(
                  value: i < ko.length ? ko[i].reviews : 0,
                  maxValue: maxValue,
                  color: colors.primary,
                ),
                const SizedBox(width: 3),
                _Bar(
                  value: i < en.length ? en[i].reviews : 0,
                  maxValue: maxValue,
                  color: colors.tertiary,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.value,
    required this.maxValue,
    required this.color,
  });

  final int value;
  final int maxValue;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: FractionallySizedBox(
        heightFactor: value == 0 ? 0.04 : value / maxValue,
        child: Container(
          width: 10,
          decoration: BoxDecoration(
            color: value == 0 ? color.withValues(alpha: .25) : color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}

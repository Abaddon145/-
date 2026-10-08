import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/core/database/app_database.dart';
import 'package:korean_memo/features/statistics/presentation/statistics_page.dart';
import 'package:korean_memo/features/statistics/domain/providers.dart';

void main() {
  testWidgets('today metrics do not include earlier days', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        recentStatisticsProvider.overrideWith((ref) async => [
          DailyStatisticsSummary(
            date: DateTime.utc(2026, 10, 6),
            newWords: 2, reviews: 8, correct: 9, wrong: 1,
            durationMs: 600000,
          ),
          DailyStatisticsSummary(
            date: DateTime.utc(2026, 10, 7),
            newWords: 1, reviews: 1, correct: 1, wrong: 1,
            durationMs: 60000,
          ),
        ]),
      ],
      child: const MaterialApp(home: StatisticsPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('正确率  50%'), findsOneWidget);
    expect(find.text('学习时长  1 分钟'), findsOneWidget);
    expect(find.textContaining('正确率 83% · 11 分钟'), findsOneWidget);
  });
}

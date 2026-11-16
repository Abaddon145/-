import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/features/study/presentation/study_content.dart';
import 'package:korean_memo/services/fsrs_service.dart';

void main() {
  testWidgets('rating buttons distinguish 认识 and 忘记', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudyActions(
            revealed: true,
            busy: false,
            onReveal: () {},
            onRate: (_) {},
            intervals: const {
              StudyRating.again: '1 分钟',
              StudyRating.hard: '5 分钟',
              StudyRating.good: '10 分钟',
              StudyRating.easy: '16 天',
            },
          ),
        ),
      ),
    );
    expect(find.widgetWithText(FilledButton, '认识'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '简单'), findsOneWidget);
    final again = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '忘记'),
    );
    expect(again.style?.backgroundColor?.resolve({}), isNotNull);
    expect(find.text('10 分钟'), findsOneWidget);
  });

  testWidgets('unrevealed study actions keep a single reveal button', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StudyActions(
            revealed: false,
            busy: false,
            onReveal: _noop,
            onRate: _noopRate,
          ),
        ),
      ),
    );
    expect(find.text('查看答案'), findsOneWidget);
    expect(find.text('认识'), findsNothing);
  });
}

void _noop() {}
void _noopRate(StudyRating _) {}

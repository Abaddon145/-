import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/core/theme/app_motion.dart';
import 'package:korean_memo/features/ai/domain/ai_models.dart';
import 'package:korean_memo/features/ai/presentation/ai_request_status.dart';
import 'package:korean_memo/features/study/presentation/study_content.dart';

void main() {
  testWidgets(
    'reduced motion leaves touch action working and disables sheet movement',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Builder(
              builder: (context) {
                expect(AppMotion.sheet(context).duration, Duration.zero);
                return Scaffold(
                  body: PressFeedback(
                    child: TextButton(
                      onPressed: () => taps++,
                      child: const Text('touch'),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('touch')),
      );
      await tester.pump();
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(taps, 1);
    },
  );
  testWidgets('scroll cancels press response without activating the button', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              PressFeedback(
                child: TextButton(
                  onPressed: () => taps++,
                  child: const Text('touch'),
                ),
              ),
              const SizedBox(height: 1600),
            ],
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('touch')),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(0, -35));
    await tester.pump();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(taps, 0);
  });
  testWidgets('large-text ratings keep card area stable and buttons tappable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var revealed = false, ratings = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    const Expanded(
                      child: Card(child: Center(child: Text('word'))),
                    ),
                    StudyActions(
                      revealed: revealed,
                      busy: false,
                      onReveal: () => setState(() => revealed = true),
                      onRate: (_) => ratings++,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final before = tester.getRect(find.byType(Card));
    await tester.tap(find.text('查看答案'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(Card)), before);
    for (final label in ['忘记', '困难', '认识', '简单']) {
      expect(
        tester.getSize(find.widgetWithText(FilledButton, label)).height,
        greaterThanOrEqualTo(48),
      );
    }
    await tester.tap(find.text('认识'));
    await tester.pumpAndSettle();
    expect(ratings, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'AI wait clock disposes and rate limit waits without auto retry',
    (tester) async {
      var cancels = 0, retries = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AiRequestStatus(onCancel: () => cancels++)),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining('2 秒'), findsOneWidget);
      await tester.tap(find.text('取消请求'));
      await tester.pump();
      expect(cancels, 1);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AiErrorNotice(
              error: const AiException('rate_limited', retryAfterSeconds: 2),
              onRetry: () => retries++,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('2 秒后可重试'), findsOneWidget);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 3)),
      );
      await tester.pump(const Duration(seconds: 3));
      expect(retries, 0);
      await tester.tap(find.text('重试本次请求'));
      await tester.pump();
      expect(retries, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    },
  );
}

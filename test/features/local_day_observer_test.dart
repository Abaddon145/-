import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/core/time/local_day.dart';

void main() {
  testWidgets('midnight refreshes the day without restarting the app', (tester) async {
    var now = DateTime(2026, 10, 8, 23, 59, 59);
    final container = ProviderContainer(overrides: [
      localDayProvider.overrideWith((ref) => DateTime(2026, 10, 8)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: LocalDayObserver(now: () => now, child: const SizedBox()),
    ));
    now = DateTime(2026, 10, 9);
    await tester.pump(const Duration(seconds: 1));
    expect(container.read(localDayProvider), DateTime(2026, 10, 9));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('resuming after suspension catches up to the current day', (tester) async {
    var now = DateTime(2026, 10, 8, 12);
    final container = ProviderContainer(overrides: [
      localDayProvider.overrideWith((ref) => DateTime(2026, 10, 8)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: LocalDayObserver(now: () => now, child: const SizedBox()),
    ));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = DateTime(2026, 10, 10, 9);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(container.read(localDayProvider), DateTime(2026, 10, 10));
    await tester.pumpWidget(const SizedBox());
  });
}

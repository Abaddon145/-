import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/core/database/app_database.dart';
import 'package:korean_memo/core/router/app_router.dart';
import 'package:korean_memo/core/theme/app_backdrop.dart';
import 'package:korean_memo/core/theme/app_theme.dart';
import 'package:korean_memo/core/theme/appearance_settings.dart';
import 'package:korean_memo/features/import/data/bundled_word_seed_service.dart';
import 'package:korean_memo/features/statistics/presentation/checkin_page.dart';
import 'package:korean_memo/features/study/domain/providers.dart';

class CountingDatabase extends AppDatabase {
  CountingDatabase() : super(NativeDatabase.memory());
  int autoReads = 0;
  @override
  Future<String?> loadSetting(String key) {
    if (key == 'auto_checkin') { autoReads++; }
    return super.loadSetting(key);
  }
}

void main() {
  testWidgets('iOS checkin push pop has no slide overlap and preserves its backdrop', (tester) async {
    final db = CountingDatabase();
    addTearDown(db.close);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    appRouter.go('/');
    await tester.pumpWidget(ProviderScope(overrides: [
      databaseProvider.overrideWithValue(db),
      appearanceProvider.overrideWith((ref) async => const AppearanceSettings(styleId: 'paper')),
      bundledWordSeedProvider.overrideWith((ref) async => const BundledSeedResult(
        importedBooks: 0, existingBooks: 0, inserted: 0, reused: 0, bundledEntries: 0)),
    ], child: MaterialApp.router(
      theme: AppTheme.forPreset(AppTheme.preset('paper')).copyWith(platform: TargetPlatform.iOS),
      routerConfig: appRouter,
    )));
    await tester.pumpAndSettle();
    expect(find.text('KoreanMemo'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      appRouter.push('/checkin');
      await tester.pumpAndSettle();
      expect(find.text('KoreanMemo').hitTestable(), findsNothing);
      expect(find.text('学习打卡').hitTestable(), findsOneWidget);
      final context = tester.element(find.byType(CheckinPage));
      expect((ModalRoute.of(context)! as PageRoute).transitionDuration, Duration.zero);
      expect(find.ancestor(of: find.byType(CheckinPage), matching: find.byType(AppBackdrop)), findsOneWidget);
      final reads = db.autoReads;
      await tester.tap(find.byTooltip('下个月'));
      await tester.pumpAndSettle();
      expect(db.autoReads, reads);
      expect(tester.takeException(), isNull);
      appRouter.pop();
      await tester.pumpAndSettle();
      expect(find.text('KoreanMemo').hitTestable(), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('checkin calendar scrolls on a narrow screen with larger text', (tester) async {
    final db = CountingDatabase();
    addTearDown(db.close);
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(home: MediaQuery(
        data: const MediaQueryData(size: Size(320, 568), textScaler: TextScaler.linear(1.5)),
        child: const CheckinPage(),
      ))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(find.text('学习后自动打卡').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(db.autoReads, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

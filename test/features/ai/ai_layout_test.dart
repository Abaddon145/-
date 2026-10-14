import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:korean_memo/core/database/app_database.dart';
import 'package:korean_memo/core/router/app_router.dart';
import 'package:korean_memo/core/theme/app_backdrop.dart';
import 'package:korean_memo/features/ai/data/ai_client.dart';
import 'package:korean_memo/features/ai/domain/ai_models.dart';
import 'package:korean_memo/features/ai/domain/ai_providers.dart';
import 'package:korean_memo/features/ai/presentation/ai_assistant_sheet.dart';
import 'package:korean_memo/features/ai/presentation/ai_settings_page.dart';
import 'package:korean_memo/features/ai/presentation/ai_tasks_page.dart';
import 'package:korean_memo/features/import/data/bundled_word_seed_service.dart';
import 'package:korean_memo/features/library/presentation/library_page.dart';
import 'package:korean_memo/features/study/domain/providers.dart';
import 'package:korean_memo/features/study/presentation/study_controller.dart';
import 'package:korean_memo/features/study/presentation/study_page.dart';
import 'fixtures.dart';

const emptySeed = BundledSeedResult(
  importedBooks: 0,
  existingBooks: 0,
  inserted: 0,
  reused: 0,
  bundledEntries: 0,
);

class CountingGateway implements AiGateway {
  int calls = 0;
  @override
  Future<AiSuggestion> generate(
    AiRequest request,
    AiCancellation cancel,
  ) async {
    calls++;
    return suggestionFor(request);
  }

  @override
  Future<String> health() async => 'test';
}

void main() {
  Future<void> narrow(
    WidgetTester tester,
    Widget widget,
    AppDatabase db, {
    double keyboard = 0,
    CountingGateway? gateway,
  }) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          bundledWordSeedProvider.overrideWith((ref) async => emptySeed),
          if (gateway != null) aiGatewayProvider.overrideWithValue(gateway),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(320, 568),
              textScaler: const TextScaler.linear(1.5),
              viewInsets: EdgeInsets.only(bottom: keyboard),
            ),
            child: Material(child: widget),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'complete preview scrolls on 320px with 1.5 text and keyboard, renders only plain text',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final word = await addAiWord(db, '시험');
      final request = AiRequest(
        requestId: const Uuid().v4(),
        word: word,
        context: '工厂设备',
        type: 'complete',
      );
      final suggestion = suggestionFor(
        request,
        changes: {
          'usageNote': '<script>alert(1)</script>',
          'exampleKo': '시험을 봐요.',
        },
      );
      final gateway = CountingGateway();
      await narrow(
        tester,
        AiAssistantSheet(word: word, initialSuggestion: suggestion),
        db,
        keyboard: 180,
        gateway: gateway,
      );
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView), const Offset(0, -1500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(gateway.calls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'AI settings adapts to keyboard and big text without querying on every build',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await narrow(tester, const AiSettingsPage(), db, keyboard: 200);
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView), const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'library selection and missing meanings fit small screens and enlarged text',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await addAiWord(db, 'acuum', meaning: '原表未提供中文释义');
      await narrow(tester, const LibraryPage(), db);
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsOneWidget);
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'learning explanation pauses timing and retains question, input, reveal and progress',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await addAiWord(db, '시험', meaning: '考试');
      const options = SessionOptions(
        daily: false,
        target: 250,
        mode: PracticeMode.spelling,
      );
      await db.startSession(options, DateTime.now());
      final gateway = CountingGateway();
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          bundledWordSeedProvider.overrideWith((ref) async => emptySeed),
          aiGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sessionOptionsProvider.notifier).start(options);
      container.read(studyVisibleProvider.notifier).state = true;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: StudyPage()),
        ),
      );
      await tester.pumpAndSettle();
      final controller = container.read(studyControllerProvider.notifier);
      final original = container.read(studyControllerProvider),
          progress = await db.loadSession(options, DateTime.now());
      await tester.enterText(find.byType(TextField), '原题输入');
      await tester.tap(find.text('AI 解释'));
      await tester.pumpAndSettle();
      expect(controller.isTiming, false);
      await tester.tap(find.text('生成建议'));
      await tester.pumpAndSettle();
      expect(gateway.calls, 1);
      expect(tester.takeException(), isNull);
      // Background + hidden study page must not resume just because the panel closes.
      controller.setAppActive(false);
      container.read(studyVisibleProvider.notifier).state = false;
      Navigator.of(tester.element(find.byType(AiAssistantSheet))).pop();
      await tester.pumpAndSettle();
      expect(controller.isTiming, false);
      controller.setAppActive(true);
      expect(controller.isTiming, false);
      container.read(studyVisibleProvider.notifier).state = true;
      expect(controller.isTiming, true);
      final current = container.read(studyControllerProvider);
      expect(current.word!.id, original.word!.id);
      expect(current.isRevealed, original.isRevealed);
      expect(
        (tester.widget<TextField>(find.byType(TextField))).controller!.text,
        '原题输入',
      );
      expect(
        (await db.loadSession(options, DateTime.now())).done,
        progress.done,
      );
      expect(await db.select(db.reviewLogs).get(), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'AI routes preserve independent backgrounds and zero transitions on repeat push/pop',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      appRouter.go('/');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            bundledWordSeedProvider.overrideWith((ref) async => emptySeed),
          ],
          child: MaterialApp.router(routerConfig: appRouter),
        ),
      );
      await tester.pumpAndSettle();
      for (final route in [
        '/settings/ai',
        '/ai/tasks',
        '/settings/ai',
        '/ai/tasks',
      ]) {
        appRouter.push(route);
        await tester.pumpAndSettle();
        final finder = route.contains('settings')
            ? find.byType(AiSettingsPage)
            : find.byType(AiTasksPage);
        final context = tester.element(finder);
        expect(
          (ModalRoute.of(context)! as PageRoute).transitionDuration,
          Duration.zero,
        );
        final backgrounds = tester.widgetList<AppBackdrop>(
          find.ancestor(of: finder, matching: find.byType(AppBackdrop)),
        );
        expect(
          backgrounds.where(
            (b) => b.child is AiSettingsPage || b.child is AiTasksPage,
          ),
          hasLength(1),
        );
        expect(tester.takeException(), isNull);
        appRouter.pop();
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );
}

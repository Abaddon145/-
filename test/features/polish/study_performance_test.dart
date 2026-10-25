import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/core/database/app_database.dart';
import 'package:korean_memo/features/import/data/bundled_word_seed_service.dart';
import 'package:korean_memo/features/study/domain/providers.dart';
import 'package:korean_memo/features/study/presentation/study_page.dart';
import 'package:korean_memo/features/settings/presentation/settings_page.dart';
import 'package:korean_memo/features/ai/domain/ai_providers.dart';
import '../ai/fixtures.dart';

class FormReads extends AppDatabase {
  FormReads() : super(NativeDatabase.memory());
  int reads = 0;
  @override
  Future<String?> loadSetting(String key) {
    if (key.startsWith('word_forms:')) reads++;
    return super.loadSetting(key);
  }
}

const emptySeed = BundledSeedResult(
  importedBooks: 0,
  existingBooks: 0,
  inserted: 0,
  reused: 0,
  bundledEntries: 0,
);
void main() {
  testWidgets('typing and checking forms reuse the scoped query', (
    tester,
  ) async {
    final db = FormReads();
    addTearDown(db.close);
    final word = await addAiWord(db, '가다', meaning: '去');
    await db.saveSetting('word_forms:${word.id}', '过去时=갔어요');
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        bundledWordSeedProvider.overrideWith((ref) async => emptySeed),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(sessionOptionsProvider.notifier)
        .start(const SessionOptions(daily: false, mode: PracticeMode.forms));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: StudyPage()),
      ),
    );
    await tester.pumpAndSettle();
    final baseline = db.reads;
    expect(baseline, 1);
    await tester.enterText(find.byType(TextField), '갔어요');
    await tester.tap(find.text('检查答案'));
    await tester.pumpAndSettle();
    expect(find.text('回答正确'), findsOneWidget);
    expect(db.reads, baseline);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('backup shortcut opens the backup controls in view', (
    tester,
  ) async {
    final db = FormReads();
    addTearDown(db.close);
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          aiKeyStoreProvider.overrideWithValue(TestAiKeyStore()),
        ],
        child: const MaterialApp(home: SettingsPage(focusBackup: true)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('每周备份提醒').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/core/database/app_database.dart';
import 'package:korean_memo/features/import/data/bundled_word_seed_service.dart';
import 'package:korean_memo/features/study/domain/providers.dart';
import 'package:korean_memo/features/study/presentation/study_page.dart';

import 'ai/fixtures.dart';

void main() {
  testWidgets('spelling field keeps a1 2b while shortcuts are active', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await addAiWord(db, '시험', meaning: '考试');
    const options = SessionOptions(
      daily: false,
      target: 20,
      mode: PracticeMode.spelling,
    );
    await db.startSession(options, DateTime.now());
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        bundledWordSeedProvider.overrideWith(
          (ref) async => const BundledSeedResult(
            importedBooks: 0,
            existingBooks: 0,
            inserted: 0,
            reused: 0,
            bundledEntries: 0,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(sessionOptionsProvider.notifier).start(options);
    container.read(studyVisibleProvider.notifier).state = true;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: StudyPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pump();

    final typed = StringBuffer();
    const keys = <(LogicalKeyboardKey, String)>[
      (LogicalKeyboardKey.keyA, 'a'),
      (LogicalKeyboardKey.digit1, '1'),
      (LogicalKeyboardKey.space, ' '),
      (LogicalKeyboardKey.digit2, '2'),
      (LogicalKeyboardKey.keyB, 'b'),
    ];
    for (final (key, character) in keys) {
      final handled = await tester.sendKeyEvent(key, character: character);
      if (!handled) typed.write(character);
    }
    expect(typed.toString(), 'a1 2b');
    await tester.enterText(find.byType(TextField), typed.toString());
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'a1 2b',
    );

    Focus.of(tester.element(find.byType(Scaffold))).requestFocus();
    await tester.pump();
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.space), isTrue);
    await tester.pump();
    expect(find.text('考试'), findsOneWidget);
  });
}

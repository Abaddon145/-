import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/core/database/app_database.dart';
import 'package:korean_memo/features/import/presentation/import_page.dart';
import 'package:korean_memo/features/study/domain/providers.dart';

void main() {
  testWidgets('CSV import is shown only in the English space', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: ImportPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('选择.xlsx文件'), findsOneWidget);
    expect(find.text('导入英语词表'), findsNothing);

    final context = tester.element(find.byType(ImportPage));
    await ProviderScope.containerOf(context)
        .read(activeLanguageProvider.notifier)
        .select('en');
    await tester.pumpAndSettle();
    expect(find.text('导入英语词表'), findsOneWidget);
    expect(find.text('选择 CSV 或 TSV'), findsOneWidget);
    expect(find.text('选择.xlsx文件'), findsNothing);
  });
}

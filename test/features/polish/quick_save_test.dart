import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:korean_memo/core/database/app_database.dart';
import 'package:korean_memo/features/study/domain/providers.dart';
import 'package:korean_memo/features/ai/data/ai_repository.dart';
import 'package:korean_memo/features/ai/domain/ai_models.dart';
import 'package:korean_memo/features/ai/presentation/ai_assistant_sheet.dart';
import '../ai/fixtures.dart';

void main() {
  Future<Word> show(WidgetTester tester, AppDatabase db) async {
    final word = await addAiWord(db, '시험', meaning: '人工确认的考试释义');
    final request = AiRequest(
      requestId: const Uuid().v4(),
      word: word,
      context: '日常韩语',
      type: 'explain',
    );
    final suggestion = suggestionFor(request);
    await AiRepository(db).store(request, suggestion);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Scaffold(
            body: AiAssistantSheet(
              word: word,
              explain: true,
              initialSuggestion: suggestion,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return word;
  }

  testWidgets(
    'explanation saves missing content directly without opening editors or overwriting meaning',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final word = await show(tester, db);
      expect(find.byType(TextField), findsNothing);
      final save = find.textContaining(RegExp(r'^保存选中的'));
      expect(save.hitTestable(), findsOneWidget);
      await tester.tap(save);
      await tester.pumpAndSettle();
      final current = (await AiRepository(db).word(word.id))!;
      expect(current.meaningZh, word.meaningZh);
      expect((await AiRepository(db).contents(current))['usageNote'], '测试用法');
      expect(await db.select(db.reviewLogs).get(), isEmpty);
      expect(find.text('已保存 · AI 生成·用户已确认').hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'compact chooser clears defaults and saves just the checked example',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final word = await show(tester, db);
      await tester.tap(find.textContaining('选择内容 ·'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清除选择'));
      await tester.pumpAndSettle();
      final example = find.widgetWithText(CheckboxListTile, '韩文例句');
      await tester.ensureVisible(example);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: example, matching: find.text('韩文例句')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('应用选择（1 项）'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存选中的 1 个字段'));
      await tester.pumpAndSettle();
      final current = (await AiRepository(db).word(word.id))!;
      expect(current.exampleKo, '시험을 봐요.');
      expect(current.exampleZh, word.exampleZh);
      expect(current.meaningZh, word.meaningZh);
      expect(
        (await AiRepository(db).contents(current)).keys,
        unorderedEquals(['exampleKo']),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

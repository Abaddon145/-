import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/core/database/app_database.dart';

void main() {
  test('special books are isolated from daily learning and searchable by book', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.importWordBookIfMissing(name: '专项', sourceFileName: 'special', drafts: [
      const WordDraft(korean: 'curl', meaningZh: '原表未提供中文释义',
        category: '工业术语·待补中文', tags: '仅英文'),
    ]);
    await db.importWordBookIfMissing(name: '普通', sourceFileName: 'normal', drafts: [
      const WordDraft(korean: '하늘', meaningZh: '天空'),
    ]);
    final books = await db.loadWordBooks();
    final special = books.first.id;
    final now = DateTime(2026, 10, 9, 12);
    expect((await db.nextStudyWord(now.toUtc(), localNow: now))?.korean, '하늘');
    expect((await db.nextStudyWord(now.toUtc(), localNow: now, bookId: special))?.korean, 'curl');
    expect((await db.searchLibraryWords(bookId: special)).map((e) => e.word.korean), ['curl']);
    expect((await db.searchLibraryWords(bookId: special, query: '天空')), isEmpty);
    expect((await db.loadScopedStudyCounts(null)).newWords, 1);
    expect((await db.loadScopedStudyCounts(special)).newWords, 1);
  });

  test('seed imports are idempotent and preserve existing definitions', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.importWordBookIfMissing(name: '原有', sourceFileName: 'original', drafts: [
      const WordDraft(korean: '얇다', meaningZh: '薄'),
    ]);
    final drafts = [const WordDraft(korean: '얇다', meaningZh: '原表未提供中文释义',
      category: '工业术语·待补中文')];
    final result = await db.importWordBookIfMissing(name: '专项', sourceFileName: 'special', drafts: drafts);
    expect(result?.reused, 1);
    expect(result?.inserted, 0);
    expect(await db.importWordBookIfMissing(name: '专项', sourceFileName: 'special', drafts: drafts), isNull);
    expect((await db.searchLibraryWords()).single.word.meaningZh, '薄');
    expect(await db.loadWordBooks(), hasLength(2));
  });
}

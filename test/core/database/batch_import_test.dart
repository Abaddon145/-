import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/core/database/app_database.dart';

void main() {
  test(
    'bulk import crosses batch boundaries, reuses duplicates and preserves existing content',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final existingId = await db.addManualWord(
        const WordDraft(korean: '기존', meaningZh: '已有释义', partOfSpeech: '名词'),
      );
      await db.setFavorite(existingId, true);
      final book = await db.createWordBook(name: '批量', sourceFileName: 'test');
      final drafts = [
        for (var i = 0; i < 805; i++)
          WordDraft(korean: '단어$i', meaningZh: '释义$i'),
        const WordDraft(korean: '단어0', meaningZh: '不覆盖'),
        const WordDraft(korean: '기존', meaningZh: '不覆盖'),
      ];
      final result = await db.importWords(
        wordBookId: book,
        drafts: drafts,
        source: 'batch-test',
      );
      expect(result.inserted, 805);
      expect(result.reused, 2);
      final words = await db.select(db.words).get();
      expect(words, hasLength(806));
      expect(words.firstWhere((w) => w.id == existingId).meaningZh, '已有释义');
      expect(words.firstWhere((w) => w.korean == '단어0').meaningZh, '释义0');
      final ids = words.map((w) => w.id).toList();
      final repeated = await db.importWords(
        wordBookId: book,
        drafts: drafts,
        source: 'repeat',
      );
      expect(repeated.inserted, 0);
      expect(repeated.reused, 807);
      expect((await db.select(db.words).get()).map((w) => w.id), ids);
      expect(
        (await db.searchLibraryWords(
          query: '기존',
          filter: LibraryFilter.favorites,
        )).single.word.id,
        existingId,
      );
      final links = await (db.select(
        db.wordBookWords,
      )..where((w) => w.wordBookId.equals(book))).get();
      expect(links, hasLength(806));
      expect(
        links
            .firstWhere(
              (l) => l.wordId == words.firstWhere((w) => w.korean == '단어0').id,
            )
            .sortOrder,
        805,
      );
    },
  );
}

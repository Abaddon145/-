import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/core/database/app_database.dart';

void main() {
  test('library editing, wrong-word tracking, and backup restore', () async {
    final source = AppDatabase(NativeDatabase.memory());
    final restored = AppDatabase(NativeDatabase.memory());
    addTearDown(source.close);
    addTearDown(restored.close);

    final bookId = await source.createWordBook(name: 'test', sourceFileName: 'test.xlsx');
    await source.importWords(wordBookId: bookId, source: 'test.xlsx',
      drafts: const [WordDraft(korean: '학교', meaningZh: '学校')]);
    final words = await source.searchLibraryWords(query: '学', filter: LibraryFilter.all);
    expect(words, hasLength(1));
    final id = words.single.word.id;

    await source.updateWord(wordId: id, korean: '학교', meaningZh: '学校/校园');
    await source.setFavorite(id, true);
    final favorite = await source.searchLibraryWords(query: '', filter: LibraryFilter.favorites);
    expect(favorite.single.word.meaningZh, '学校/校园');

    final now = DateTime.now();
    await source.persistReview(
      wordId: id, submissionToken: 'test-review', rating: 1,
      reviewedAt: now.toUtc(), durationMs: 1200, localDay: now,
      cardMap: {'state': 1, 'due': now.toUtc().toIso8601String(), 'stability': 1.0,
        'difficulty': 5.0, 'elapsed_days': 0, 'scheduled_days': 1,
        'reps': 1, 'lapses': 1, 'last_review': now.toUtc().toIso8601String()},
      reviewLogMap: {'elapsed_days': 0, 'scheduled_days': 1},
    );
    final wrong = await source.searchLibraryWords(query: '', filter: LibraryFilter.wrong);
    expect(wrong.single.wrongCount, 1);

    final snapshot = await source.createBackupSnapshot();
    await restored.restoreBackupSnapshot(snapshot);
    final restoredWord = await restored.searchLibraryWords(query: '学校', filter: LibraryFilter.favorites);
    expect(restoredWord.single.word.meaningZh, '学校/校园');
    expect(restoredWord.single.wrongCount, 1);
    final progress = await restored.loadDailyPlanProgress(now);
    expect(progress.newWordsDone, 1);
    expect(progress.wrongCount, 1);
  });

  test('invalid backup is rejected before replacing existing data', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final bookId = await database.createWordBook(name: 'keep', sourceFileName: 'keep.xlsx');
    await database.importWords(wordBookId: bookId, source: 'keep.xlsx',
      drafts: const [WordDraft(korean: '남다', meaningZh: '留下')]);
    expect(() => database.restoreBackupSnapshot({'format': 'wrong'}),
      throwsA(isA<FormatException>()));
    expect(await database.searchLibraryWords(query: '', filter: LibraryFilter.all), hasLength(1));
  });
}

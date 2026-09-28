import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/core/database/app_database.dart';

void main() {
  test('manual word keeps its part of speech and rejects duplicates', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    final id = await database.addManualWord(
      const WordDraft(korean: '달리다', meaningZh: '跑', partOfSpeech: '动词'),
    );
    final words = await database.searchLibraryWords(
      query: '달리다',
      filter: LibraryFilter.all,
    );
    expect(words.single.word.id, id);
    expect(words.single.word.partOfSpeech, '动词');

    await database.updateWord(
      wordId: id,
      korean: '달리다',
      meaningZh: '奔跑',
      partOfSpeech: '自动词',
    );
    final edited = await database.searchLibraryWords(
      query: '奔跑',
      filter: LibraryFilter.all,
    );
    expect(edited.single.word.partOfSpeech, '自动词');

    await expectLater(
      database.addManualWord(
        const WordDraft(korean: '달리다', meaningZh: '跑', partOfSpeech: '动词'),
      ),
      throwsA(isA<FormatException>()),
    );
    final all = await database.searchLibraryWords(
      query: '',
      filter: LibraryFilter.all,
    );
    expect(all, hasLength(1));
  });

  test('appearance settings travel with a progress backup', () async {
    final source = AppDatabase(NativeDatabase.memory());
    final destination = AppDatabase(NativeDatabase.memory());
    addTearDown(source.close);
    addTearDown(destination.close);

    await source.saveSetting('appearance_style', 'forest');
    await source.saveSetting('appearance_background_base64', 'aGVsbG8=');
    await source.addManualWord(
      const WordDraft(korean: '나무', meaningZh: '树', partOfSpeech: '名词'),
    );
    await destination.restoreBackupSnapshot(
      await source.createBackupSnapshot(),
    );

    expect(await destination.loadSetting('appearance_style'), 'forest');
    expect(await destination.loadSetting('appearance_background_base64'),
        'aGVsbG8=');
    final words = await destination.searchLibraryWords(
      query: '나무',
      filter: LibraryFilter.all,
    );
    expect(words.single.word.partOfSpeech, '名词');
  });
}

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/features/import/data/bundled_word_seed_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled vocabulary contains all three uploaded workbooks', () async {
    final raw = await rootBundle.loadString(BundledWordSeedService.assetPath);
    final books = const BundledWordSeedService().decode(raw);

    expect(books.map((book) => book.name), ['单词01', '单词02', '单词03']);
    expect(books.map((book) => book.drafts.length), [2610, 229, 264]);

    final drafts = books.expand((book) => book.drafts).toList();
    expect(drafts, hasLength(3103));
    expect(drafts.every((word) => word.korean.trim().isNotEmpty), isTrue);
    expect(drafts.every((word) => word.meaningZh.trim().isNotEmpty), isTrue);
  });
}

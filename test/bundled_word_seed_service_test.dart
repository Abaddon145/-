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
  test('technical tables retain translated terms and isolate untranslated entries', () async {
    final books = const BundledWordSeedService().decode(
      await rootBundle.loadString(BundledWordSeedService.technicalAssetPath));
    expect(books.map((book) => book.drafts.length), [256, 283, 42]);
    final special = books.last.drafts;
    expect(special.every((word) => word.meaningZh == '原表未提供中文释义'), isTrue);
    expect(special.every((word) => word.category == '工业术语·待补中文'), isTrue);
    expect(special.where((word) => word.tags == '英韩配对'), hasLength(22));
    expect(special.where((word) => word.tags == '仅英文'), hasLength(14));
    expect(special.where((word) => word.tags == '仅韩文'), hasLength(6));
    final all = books.expand((book) => book.drafts).map((word) => word.korean);
    expect(all, isNot(contains('激光刀')));
    expect(all, isNot(contains('喷码')));
    expect(all, isNot(contains('之类的')));
  });
}

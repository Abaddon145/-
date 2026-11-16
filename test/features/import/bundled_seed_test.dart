import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/core/database/app_database.dart';
import 'package:korean_memo/features/import/data/bundled_word_seed_service.dart';

void main() {
  test('bundled word books are parsed only on the first import', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final first = await const BundledWordSeedService().seed(database);
    expect(first.inserted, greaterThan(0));
    expect(await database.loadSetting(bundledSeedMarkerKey), bundledSeedMarker);
    final words = await database.select(database.words).get();
    final second = await const BundledWordSeedService().seed(database);
    expect(second.inserted, 0);
    expect(second.importedBooks, 0);
    expect((await database.select(database.words).get()).length, words.length);
  });
}

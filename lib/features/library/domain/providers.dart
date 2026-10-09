import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../study/domain/providers.dart';

final librarySearchProvider = StateProvider.autoDispose<String>((ref) => '');
final libraryFilterProvider =
    StateProvider.autoDispose<LibraryFilter>((ref) => LibraryFilter.all);
final libraryBookProvider = StateProvider.autoDispose<int?>((ref) => null);

final libraryWordsProvider =
    FutureProvider.autoDispose<List<LibraryWordEntry>>((ref) async {
  final database = ref.watch(databaseProvider);
  final query = ref.watch(librarySearchProvider);
  final filter = ref.watch(libraryFilterProvider);
  final bookId = ref.watch(libraryBookProvider);
  await ref.watch(bundledWordSeedProvider.future);
  return database.searchLibraryWords(
        query: query,
        filter: filter,
        bookId: bookId,
      );
});


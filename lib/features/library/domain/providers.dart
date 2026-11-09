import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../study/domain/providers.dart';

final librarySearchProvider = StateProvider.autoDispose<String>((ref) => '');
final libraryFilterProvider =
    StateProvider.autoDispose<LibraryFilter>((ref) => LibraryFilter.all);
final libraryBookProvider = StateProvider.autoDispose<int?>((ref) => null);

const libraryPageSize = 40;

final libraryLimitProvider = StateProvider.autoDispose<int>((ref) => libraryPageSize);

final libraryWordsProvider =
    FutureProvider.autoDispose<List<LibraryWordEntry>>((ref) async {
  final database = ref.watch(databaseProvider);
  final query = ref.watch(librarySearchProvider);
  final filter = ref.watch(libraryFilterProvider);
  final limit = ref.watch(libraryLimitProvider);
  await ref.watch(bundledWordSeedProvider.future);
  return database.searchLibraryWords(
        query: query,
        filter: filter,
        bookId: ref.watch(libraryBookProvider),
        limit: limit,
      );
});

final libraryCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final database = ref.watch(databaseProvider);
  await ref.watch(bundledWordSeedProvider.future);
  return database.countLibraryWords(
    query: ref.watch(librarySearchProvider),
    filter: ref.watch(libraryFilterProvider),
    bookId: ref.watch(libraryBookProvider),
  );
});


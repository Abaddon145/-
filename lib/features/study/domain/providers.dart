import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../services/fsrs_service.dart';
import '../../../services/tts_service.dart';
import '../../import/data/bundled_word_seed_service.dart';
import '../data/study_repository.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final fsrsServiceProvider = Provider<FsrsService>((ref) => FsrsService());

final ttsServiceProvider = Provider<TtsService>((ref) {
  final service = TtsService();
  ref.onDispose(service.dispose);
  return service;
});

final studyRepositoryProvider = Provider<StudyRepository>((ref) {
  return StudyRepository(
    ref.watch(databaseProvider),
    ref.watch(fsrsServiceProvider),
  );
});

final bundledWordSeedProvider = FutureProvider<BundledSeedResult>((ref) {
  return const BundledWordSeedService().seed(ref.watch(databaseProvider));
});

final homeCountsProvider = FutureProvider.autoDispose<HomeCounts>((ref) async {
  await ref.watch(bundledWordSeedProvider.future);
  return ref.watch(databaseProvider).loadHomeCounts(DateTime.now().toUtc());
});

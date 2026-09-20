import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../services/fsrs_service.dart';
import '../../../services/tts_service.dart';
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

final homeCountsProvider = FutureProvider.autoDispose<HomeCounts>((ref) {
  return ref.watch(databaseProvider).loadHomeCounts(DateTime.now().toUtc());
});

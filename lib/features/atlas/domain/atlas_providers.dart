import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/time/local_day.dart';
import '../../study/domain/providers.dart';
import '../../statistics/domain/providers.dart';
import '../data/atlas_media_cache.dart';
import '../data/atlas_remote.dart';
import '../data/atlas_store.dart';
import '../domain/atlas_models.dart';

final atlasMediaCacheProvider = Provider<AtlasMediaCache>((ref) {
  final cache = AtlasMediaCache(
    opening: openAtlasStore(),
    maxBytes: atlasCacheMaxBytes,
    fetcher: fetchAtlasBytes,
  );
  return cache;
});

final todayJourneyProvider = FutureProvider.autoDispose<TodayJourney>((
  ref,
) async {
  ref.watch(localDayProvider);
  await ref.watch(bundledWordSeedProvider.future);
  return ref
      .watch(databaseProvider)
      .loadTodayJourney(DateTime.now(), ref.watch(activeLanguageProvider));
});

final atlasStatsProvider = FutureProvider.autoDispose<AtlasStats>((ref) async {
  ref.watch(localDayProvider);
  final database = ref.watch(databaseProvider);
  if (statisticsCombine(ref)) {
    final korean = await database.loadAtlasStats('ko');
    final english = await database.loadAtlasStats('en');
    return AtlasStats(
      mastered: korean.mastered + english.mastered,
      firstCorrect: korean.firstCorrect + english.firstCorrect,
      firstAttempts: korean.firstAttempts + english.firstAttempts,
    );
  }
  return database.loadAtlasStats(statisticsLanguageOf(ref));
});

final englishAccentProvider = FutureProvider.autoDispose<String>((ref) async {
  final raw = await ref.watch(databaseProvider).loadSetting(englishAccentKey);
  return normalizeEnglishAccent(raw);
});

final uiSoundsProvider = FutureProvider.autoDispose<bool>((ref) async {
  final raw = await ref.watch(databaseProvider).loadSetting(uiSoundsKey);
  return raw != 'false';
});

final atlasCacheBytesProvider = FutureProvider.autoDispose<int>((ref) {
  return ref.watch(atlasMediaCacheProvider).sizeBytes();
});

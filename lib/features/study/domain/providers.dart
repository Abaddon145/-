import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/language/learning_language.dart';
import '../../../core/time/local_day.dart';
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

class ActiveLanguageController extends StateNotifier<String> {
  ActiveLanguageController(this.database) : super('ko') {
    reload();
  }

  final AppDatabase database;

  Future<void> reload() async {
    final saved = await database.loadSetting(activeLanguageSettingKey);
    if (!mounted) return;
    state = normalizeLearningLanguage(saved);
  }

  Future<void> select(String language) async {
    final next = normalizeLearningLanguage(language);
    if (next == state) return;
    final previous = state;
    state = next;
    try {
      await database.saveSetting(activeLanguageSettingKey, next);
    } catch (_) {
      if (mounted && state == next) state = previous;
    }
  }
}

final activeLanguageProvider =
    StateNotifierProvider<ActiveLanguageController, String>((ref) {
      return ActiveLanguageController(ref.watch(databaseProvider));
    });

final studyBookProvider = StateProvider<int?>((ref) => null);
final studyVisibleProvider = StateProvider<bool>((ref) => false);
final studyHasCardProvider = StateProvider<bool>((ref) => false);

class SessionOptionsController extends StateNotifier<SessionOptions> {
  SessionOptionsController(this.database, String language)
    : super(SessionOptions(language: normalizeLearningLanguage(language))) {
    _restore();
  }
  final AppDatabase database;
  int _version = 0;
  Future<void> _restore() async {
    final version = _version;
    final raw = await database.loadSetting(
      scopedSetting(state.language, 'selected_learning_session'),
    );
    if (!mounted || raw == null || version != _version) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['day'] == dayKey(DateTime.now())) {
        state = SessionOptions.fromJson(data);
      }
    } catch (_) {
      /* Invalid preferences fall back to the daily queue. */
    }
  }

  Future<void> start(SessionOptions options) async {
    _version++;
    await database.startSession(options, DateTime.now());
    if (mounted) state = options;
  }

  Future<void> daily() async {
    _version++;
    final language = state.language;
    state = SessionOptions(language: language);
    await database.saveSetting(
      scopedSetting(language, 'selected_learning_session'),
      null,
    );
  }
}

final sessionOptionsProvider =
    StateNotifierProvider<SessionOptionsController, SessionOptions>((ref) {
      final controller = SessionOptionsController(
        ref.watch(databaseProvider),
        ref.watch(activeLanguageProvider),
      );
      ref.listen(localDayProvider, (_, _) => controller.daily());
      return controller;
    });
final sessionProgressProvider = FutureProvider.autoDispose<SessionProgress>((
  ref,
) {
  ref.watch(localDayProvider);
  return ref
      .watch(databaseProvider)
      .loadSession(ref.watch(sessionOptionsProvider), DateTime.now());
});
final checkinsProvider = FutureProvider.autoDispose<CheckinSummary>((ref) {
  ref.watch(localDayProvider);
  final language = ref.watch(activeLanguageProvider);
  return ref.watch(databaseProvider).loadCheckins(DateTime.now(), language);
});

final studyRepositoryProvider = Provider<StudyRepository>((ref) {
  return StudyRepository(
    ref.watch(databaseProvider),
    ref.watch(fsrsServiceProvider),
    options: ref.watch(sessionOptionsProvider),
  );
});

final bundledWordSeedProvider = FutureProvider<BundledSeedResult>((ref) {
  return const BundledWordSeedService().seed(ref.watch(databaseProvider));
});

final homeCountsProvider = FutureProvider.autoDispose<HomeCounts>((ref) async {
  ref.watch(localDayProvider);
  await ref.watch(bundledWordSeedProvider.future);
  final language = ref.watch(activeLanguageProvider);
  return ref
      .watch(databaseProvider)
      .loadHomeCounts(DateTime.now().toUtc(), language);
});

final dailyPlanSettingsProvider = FutureProvider.autoDispose<DailyPlanSettings>(
  (ref) {
    return ref
        .watch(databaseProvider)
        .loadDailyPlanSettings(ref.watch(activeLanguageProvider));
  },
);

final dailyPlanProgressProvider = FutureProvider.autoDispose<DailyPlanProgress>(
  (ref) async {
    ref.watch(localDayProvider);
    await ref.watch(bundledWordSeedProvider.future);
    return ref
        .watch(databaseProvider)
        .loadDailyPlanProgress(
          DateTime.now(),
          ref.watch(activeLanguageProvider),
        );
  },
);

final studyRoundProgressProvider =
    FutureProvider.autoDispose<StudyRoundProgress>((ref) async {
      ref.watch(localDayProvider);
      final database = ref.watch(databaseProvider);
      await ref.watch(bundledWordSeedProvider.future);
      return database.loadStudyRoundProgress(
        DateTime.now(),
        ref.watch(activeLanguageProvider),
      );
    });

final studyBookCountsProvider = FutureProvider.autoDispose<HomeCounts>((
  ref,
) async {
  ref.watch(localDayProvider);
  final bookId = ref.watch(studyBookProvider);
  final db = ref.watch(databaseProvider);
  await ref.watch(bundledWordSeedProvider.future);
  return db.loadScopedStudyCounts(bookId, ref.watch(activeLanguageProvider));
});

final wordBooksProvider = FutureProvider.autoDispose<List<WordBook>>((
  ref,
) async {
  final db = ref.watch(databaseProvider);
  await ref.watch(bundledWordSeedProvider.future);
  return db.loadWordBooks(ref.watch(activeLanguageProvider));
});

// Scoped futures are reused during input, reveal and animation rebuilds.
final studyWordFormsProvider = FutureProvider.autoDispose.family<String, int>(
  (ref, id) async =>
      await ref.watch(databaseProvider).loadSetting('word_forms:$id') ?? '',
);
final studyFavoriteProvider = FutureProvider.autoDispose.family<bool, int>((
  ref,
  id,
) async {
  final db = ref.watch(databaseProvider);
  return (await (db.select(
        db.userWords,
      )..where((r) => r.wordId.equals(id))).getSingleOrNull())?.isFavorite ??
      false;
});

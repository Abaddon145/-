import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/time/local_day.dart';
import '../../../services/fsrs_service.dart';
import '../data/study_repository.dart';
import '../../library/domain/providers.dart';
import '../../statistics/domain/providers.dart';
import '../domain/providers.dart';

class StudyUiState {
  const StudyUiState({
    this.word,
    this.isLoading = false,
    this.isRevealed = false,
    this.isSubmitting = false,
    this.error,
  });

  final Word? word;
  final bool isLoading;
  final bool isRevealed;
  final bool isSubmitting;
  final Object? error;

  bool get isComplete => !isLoading && word == null && error == null;

  StudyUiState copyWith({
    Word? word,
    bool clearWord = false,
    bool? isLoading,
    bool? isRevealed,
    bool? isSubmitting,
    Object? error,
    bool clearError = false,
  }) {
    return StudyUiState(
      word: clearWord ? null : (word ?? this.word),
      isLoading: isLoading ?? this.isLoading,
      isRevealed: isRevealed ?? this.isRevealed,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class StudyController extends StateNotifier<StudyUiState> {
  StudyController(this._repository, {this.onRatingSaved, this.beforeLoad})
      : super(const StudyUiState(isLoading: true));

  final StudyRepository _repository;
  final void Function()? onRatingSaved;
  final Future<void> Function()? beforeLoad;
  DateTime _shownAt = DateTime.now();
  int _loadVersion = 0;

  Future<void> load() async {
    if (!mounted) return;
    final version = ++_loadVersion;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await beforeLoad?.call();
      if (!mounted || version != _loadVersion) return;
      final word = await _repository.nextWord();
      if (!mounted || version != _loadVersion) return;
      _shownAt = DateTime.now();
      state = StudyUiState(word: word);
    } catch (error) {
      if (!mounted || version != _loadVersion) return;
      state = StudyUiState(error: error);
    }
  }

  void refreshForNewDay() {
    if (mounted && !state.isSubmitting) load();
  }

  void reveal() {
    if (state.word != null) state = state.copyWith(isRevealed: true);
  }

  Future<void> rate(StudyRating rating) async {
    final word = state.word;
    if (word == null || state.isLoading || state.isSubmitting || !state.isRevealed) return;
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      await _repository.submitRating(
        word: word,
        rating: rating,
        duration: DateTime.now().difference(_shownAt),
      );
      if (!mounted) return;
      onRatingSaved?.call();
      await load();
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(isSubmitting: false, error: error);
    }
  }
}

final studyControllerProvider =
    StateNotifierProvider.autoDispose<StudyController, StudyUiState>((ref) {
  final controller = StudyController(
    ref.watch(studyRepositoryProvider),
    beforeLoad: () async {
      await ref.read(bundledWordSeedProvider.future);
    },
    onRatingSaved: () {
      ref.invalidate(homeCountsProvider);
      ref.invalidate(dailyPlanProgressProvider);
      ref.invalidate(recentStatisticsProvider);
      ref.invalidate(libraryWordsProvider);
    },
  );
  ref.listen(localDayProvider, (_, _) {
    // An in-flight rating will load the next word after its transaction completes.
    controller.refreshForNewDay();
  });
  controller.load();
  return controller;
});

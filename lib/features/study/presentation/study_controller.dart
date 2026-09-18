import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../services/fsrs_service.dart';
import '../data/study_repository.dart';
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
  StudyController(this._repository) : super(const StudyUiState(isLoading: true));

  final StudyRepository _repository;
  DateTime _shownAt = DateTime.now();

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final word = await _repository.nextWord();
      _shownAt = DateTime.now();
      state = StudyUiState(word: word);
    } catch (error) {
      state = StudyUiState(error: error);
    }
  }

  void reveal() {
    if (state.word != null) state = state.copyWith(isRevealed: true);
  }

  Future<void> rate(StudyRating rating) async {
    final word = state.word;
    if (word == null || state.isSubmitting || !state.isRevealed) return;
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      await _repository.submitRating(
        word: word,
        rating: rating,
        duration: DateTime.now().difference(_shownAt),
      );
      await load();
    } catch (error) {
      state = state.copyWith(isSubmitting: false, error: error);
    }
  }
}

final studyControllerProvider =
    StateNotifierProvider.autoDispose<StudyController, StudyUiState>((ref) {
  final controller = StudyController(ref.watch(studyRepositoryProvider));
  controller.load();
  return controller;
});

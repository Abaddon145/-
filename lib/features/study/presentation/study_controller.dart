import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/time/local_day.dart';
import '../../../services/fsrs_service.dart';
import '../data/study_repository.dart';
import '../../home/presentation/visible_tab.dart';
import '../../library/domain/providers.dart';
import '../domain/providers.dart';

class StudyUiState {
  const StudyUiState({
    this.word,
    this.isLoading = false,
    this.isRevealed = false,
    this.isSubmitting = false,
    this.error,
    this.notice,
    this.intervals = const {},
  });

  final Word? word;
  final bool isLoading;
  final bool isRevealed;
  final bool isSubmitting;
  final Object? error;
  final String? notice;
  final Map<StudyRating, String> intervals;

  bool get isComplete => !isLoading && word == null && error == null;

  StudyUiState copyWith({
    Word? word,
    bool clearWord = false,
    bool? isLoading,
    bool? isRevealed,
    bool? isSubmitting,
    Object? error,
    bool clearError = false,
    String? notice,
    bool clearNotice = false,
    Map<StudyRating, String>? intervals,
    bool clearIntervals = false,
  }) {
    return StudyUiState(
      word: clearWord ? null : (word ?? this.word),
      isLoading: isLoading ?? this.isLoading,
      isRevealed: isRevealed ?? this.isRevealed,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: clearError ? null : (error ?? this.error),
      notice: clearNotice ? null : (notice ?? this.notice),
      intervals: clearIntervals ? const {} : (intervals ?? this.intervals),
    );
  }
}

class StudyController extends StateNotifier<StudyUiState> {
  StudyController(this._repository, {this.onRatingSaved, this.beforeLoad})
      : super(const StudyUiState(isLoading: true));

  final StudyRepository _repository;
  final void Function()? onRatingSaved;
  final Future<void> Function()? beforeLoad;
  final Stopwatch _clock = Stopwatch();
  bool _visible = true;
  bool _appActive = true;
  int _panelDepth = 0;
  void pauseForPanel() {if (!mounted) return; _panelDepth++; _syncClock();}
  void resumeFromPanel() {if (!mounted) return; if (_panelDepth > 0) _panelDepth--; _syncClock();}
  Duration get effectiveStudyTime => _clock.elapsed;
  bool get isTiming => _clock.isRunning;
  void setVisible(bool value) { if(!mounted)return; _visible = value; _syncClock(); }
  void setAppActive(bool value) { if(!mounted)return; _appActive = value; _syncClock(); }
  void _syncClock() {
    if (_visible && _appActive && _panelDepth == 0 && state.word != null && !state.isLoading && !state.isSubmitting) {
      _clock.start();
    } else { _clock.stop(); }
  }
  int _loadVersion = 0;
  int? _preparedWordId;
  Map<StudyRating, FsrsReviewResult>? _prepared;

  void _clearPrepared() {
    _preparedWordId = null;
    _prepared = null;
  }

  Future<void> load() async {
    if (!mounted) return;
    final version = ++_loadVersion;
    state = state.copyWith(isLoading: true, clearError: true);
    _clock.stop();
    try {
      await beforeLoad?.call();
      if (!mounted || version != _loadVersion) return;
      final word = await _repository.nextWord();
      if (!mounted || version != _loadVersion) return;
      _clock.reset();
      _clearPrepared();
      state = StudyUiState(word: word);
      _syncClock();
    } catch (error) {
      if (!mounted || version != _loadVersion) return;
      state = StudyUiState(error: error);
    }
  }

  Future<void> startExtraRound(int count) async {
    if (!mounted || state.isLoading || state.isSubmitting) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.startExtraRound(count);
      if (!mounted) return;
      onRatingSaved?.call();
      await load();
    } catch (error) {
      if (!mounted) return;
      state = StudyUiState(error: error);
    }
  }

  void refreshForNewDay() {
    if (mounted && !state.isSubmitting) load();
  }

  void reveal() {
    if (state.word == null || state.isRevealed) return;
    state = state.copyWith(isRevealed: true);
    prepareRatings();
  }

  Future<void> prepareRatings() async {
    final word = state.word;
    if (word == null) return;
    try {
      final preview = await _repository.preview(word);
      if (!mounted || state.word?.id != word.id) return;
      _preparedWordId = word.id;
      _prepared = preview.ratings;
      state = state.copyWith(
        intervals: {
          for (final entry in preview.ratings.entries)
            entry.key: entry.value.intervalLabel,
        },
      );
    } catch (_) {
      if (!mounted) return;
      _clearPrepared();
      state = state.copyWith(clearIntervals: true);
    }
  }

  Future<void> undo() async {
    if (state.isSubmitting || state.isLoading) return;
    try {
      final word = await _repository.undo();
      if (!mounted || word == null) return;
      _clock..stop()..reset();
      _clearPrepared();
      state = StudyUiState(word: word);
      _syncClock();
      onRatingSaved?.call();
    } catch (error) {
      if (mounted) state = state.copyWith(error: error);
    }
  }

  Future<void> rate(StudyRating rating) async {
    final word = state.word;
    if (word == null || state.isLoading || state.isSubmitting || !state.isRevealed) {
      return;
    }
    state = state.copyWith(isSubmitting: true, clearError: true, clearNotice: true);
    _clock.stop();
    try {
      if (_preparedWordId != word.id || _prepared == null || !_prepared!.containsKey(rating)) {
        await prepareRatings();
      }
      final FsrsReviewResult? prepared = _preparedWordId == word.id && _prepared != null
          ? _prepared![rating]
          : null;
      final outcome = await _repository.submitRating(
        word: word,
        rating: rating,
        duration: _clock.elapsed,
        prepared: prepared,
      );
      if (!mounted) return;
      final notice = outcome.leechSuspended
          ? '「${word.korean}」已忘记 ${outcome.lapses} 次，已暂停并列入待强化。打开词条详情，点「恢复正常学习」即可继续。'
          : null;
      onRatingSaved?.call();
      await load();
      if (!mounted || notice == null) return;
      state = state.copyWith(notice: notice);
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(isSubmitting: false, error: error);
      _syncClock();
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
      ref.invalidate(dailyPlanProgressProvider);
      ref.invalidate(studyRoundProgressProvider);
      ref.invalidate(sessionProgressProvider);
      if (ref.read(visibleTabProvider) == 0) {
        ref.invalidate(homeCountsProvider);
      }
      if (ref.read(visibleTabProvider) == 1) {
        ref.invalidate(libraryWordsProvider);
        ref.invalidate(libraryCountProvider);
      }
    },
  );
  ref.listen(localDayProvider, (_, _) {
    // An in-flight rating will load the next word after its transaction completes.
    controller.refreshForNewDay();
  });
  controller.load();
  controller.setVisible(ref.read(studyVisibleProvider));
  ref.listen(studyVisibleProvider, (_, value) => controller.setVisible(value));
  return controller;
});

import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../services/fsrs_service.dart';

class StudyRepository {
  StudyRepository(
    this._database,
    this._fsrsService, {
    this.bookId,
    this.options = const SessionOptions(),
  });

  final int? bookId;
  final SessionOptions options;
  final AppDatabase _database;
  final FsrsService _fsrsService;
  final Uuid _uuid = const Uuid();

  Future<void> startExtraRound(int count) {
    return _database.startExtraStudyRound(DateTime.now(), count);
  }

  Future<Word?> nextWord() {
    final now = DateTime.now();
    return _database.nextTrainingWord(options, now);
  }

  Future<Word?> undo() => _database.undoLastReview(DateTime.now());

  Future<bool> canUndo() => _database.canUndoReview(DateTime.now());

  Future<double> desiredRetention() async => normalizeDesiredRetention(
    await _database.loadSetting(retentionSettingKey),
  );

  /// One scheduler and one UTC timestamp for every button, so the label the
  /// learner taps is the schedule that gets stored.
  Future<({DateTime reviewedAt, Map<StudyRating, FsrsReviewResult> ratings})>
  preview(Word word) async {
    final reviewedAt = DateTime.now().toUtc();
    final currentCard = await _database.cardForWord(word.id);
    final ratings = _fsrsService.preview(
      wordId: word.id,
      storedCardJson: currentCard?.fsrsJson,
      reviewDateTime: reviewedAt,
      desiredRetention: await desiredRetention(),
    );
    return (reviewedAt: reviewedAt, ratings: ratings);
  }

  Future<ReviewWriteResult> submitRating({
    required Word word,
    required StudyRating rating,
    required Duration duration,
    FsrsReviewResult? prepared,
  }) async {
    final result = prepared ?? (await preview(word)).ratings[rating]!;
    return _database.persistReview(
      wordId: word.id,
      submissionToken: _uuid.v4(),
      rating: result.ratingValue,
      reviewedAt: result.reviewedAt,
      durationMs: duration.inMilliseconds,
      localDay: result.reviewedAt.toLocal(),
      cardMap: result.card,
      reviewLogMap: result.reviewLog,
      session: options,
    );
  }
}

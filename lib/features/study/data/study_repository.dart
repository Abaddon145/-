import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../services/fsrs_service.dart';

class StudyRepository {
  StudyRepository(this._database, this._fsrsService);

  final AppDatabase _database;
  final FsrsService _fsrsService;
  final Uuid _uuid = const Uuid();

  Future<Word?> nextWord() {
    final now = DateTime.now();
    return _database.nextStudyWord(now.toUtc(), localNow: now);
  }

  Future<void> submitRating({
    required Word word,
    required StudyRating rating,
    required Duration duration,
  }) async {
    final now = DateTime.now();
    final currentCard = await _database.cardForWord(word.id);
    final result = _fsrsService.review(
      wordId: word.id,
      storedCardJson: currentCard?.fsrsJson,
      rating: rating,
    );
    await _database.persistReview(
      wordId: word.id,
      submissionToken: _uuid.v4(),
      rating: result.ratingValue,
      reviewedAt: now.toUtc(),
      durationMs: duration.inMilliseconds,
      localDay: now,
      cardMap: result.card,
      reviewLogMap: result.reviewLog,
    );
  }
}

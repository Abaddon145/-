import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../services/fsrs_service.dart';

class StudyRepository {
  StudyRepository(this._database, this._fsrsService);

  final AppDatabase _database;
  final FsrsService _fsrsService;
  final Uuid _uuid = const Uuid();

  Future<Word?> nextWord() => _database.nextStudyWord(DateTime.now().toUtc());

  Future<void> submitRating({
    required Word word,
    required StudyRating rating,
    required Duration duration,
  }) async {
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
      reviewedAt: DateTime.now().toUtc(),
      durationMs: duration.inMilliseconds,
      cardMap: result.card,
      reviewLogMap: result.reviewLog,
    );
  }
}

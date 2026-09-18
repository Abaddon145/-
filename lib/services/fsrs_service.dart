import 'dart:convert';

import 'package:fsrs/fsrs.dart' as fsrs;

enum StudyRating { again, hard, good, easy }

class FsrsReviewResult {
  const FsrsReviewResult({
    required this.card,
    required this.reviewLog,
    required this.ratingValue,
  });

  final Map<String, Object?> card;
  final Map<String, Object?> reviewLog;
  final int ratingValue;
}

class FsrsService {
  FsrsService() : _scheduler = fsrs.Scheduler();

  final fsrs.Scheduler _scheduler;

  FsrsReviewResult review({
    required int wordId,
    required String? storedCardJson,
    required StudyRating rating,
  }) {
    final currentCard = storedCardJson == null
        ? fsrs.Card(cardId: wordId)
        : fsrs.Card.fromMap(
            (jsonDecode(storedCardJson) as Map).cast<String, dynamic>(),
          );
    final fsrsRating = switch (rating) {
      StudyRating.again => fsrs.Rating.again,
      StudyRating.hard => fsrs.Rating.hard,
      StudyRating.good => fsrs.Rating.good,
      StudyRating.easy => fsrs.Rating.easy,
    };
    final (:card, :reviewLog) =
        _scheduler.reviewCard(currentCard, fsrsRating);
    return FsrsReviewResult(
      card: card.toMap().cast<String, Object?>(),
      reviewLog: reviewLog.toMap().cast<String, Object?>(),
      ratingValue: rating.index + 1,
    );
  }
}

import 'dart:convert';

import 'package:fsrs/fsrs.dart' as fsrs;

enum StudyRating { again, hard, good, easy }

const retentionSettingKey = 'fsrs_desired_retention';
const retentionChoices = <double>[0.85, 0.90, 0.95];
const leechLapseThreshold = 8;

double normalizeDesiredRetention(String? raw) {
  final value = double.tryParse(raw ?? '');
  if (value == null) return 0.9;
  double? nearest;
  var nearestGap = 1.0;
  for (final choice in retentionChoices) {
    final gap = (value - choice).abs();
    if (gap < nearestGap) {
      nearest = choice;
      nearestGap = gap;
    }
  }
  return nearestGap <= 0.02 ? nearest! : 0.9;
}

String formatFsrsInterval(DateTime reviewUtc, DateTime due) {
  final delta = due.difference(reviewUtc);
  if (delta.inMinutes < 1) return '不到 1 分钟';
  if (delta.inMinutes < 60) return '${delta.inMinutes} 分钟';
  if (delta.inHours < 24) return '${delta.inHours} 小时';
  if (delta.inDays < 30) return '${delta.inDays} 天';
  if (delta.inDays < 365) return '${(delta.inDays / 30).round()} 个月';
  return '${(delta.inDays / 365).round()} 年';
}

class FsrsReviewResult {
  const FsrsReviewResult({
    required this.card,
    required this.reviewLog,
    required this.ratingValue,
    required this.reviewedAt,
    required this.intervalLabel,
  });

  final Map<String, Object?> card;
  final Map<String, Object?> reviewLog;
  final int ratingValue;
  final DateTime reviewedAt;
  final String intervalLabel;
}

class FsrsService {
  Map<StudyRating, FsrsReviewResult> preview({
    required int wordId,
    required String? storedCardJson,
    required DateTime reviewDateTime,
    required double desiredRetention,
  }) {
    final reviewedAt = _utc(reviewDateTime);
    final scheduler = fsrs.Scheduler(desiredRetention: desiredRetention);
    final card = _card(wordId, storedCardJson);
    return {
      for (final rating in StudyRating.values)
        rating: _apply(scheduler, card, rating, reviewedAt),
    };
  }

  FsrsReviewResult review({
    required int wordId,
    required String? storedCardJson,
    required StudyRating rating,
    DateTime? reviewDateTime,
    double desiredRetention = 0.9,
  }) {
    final reviewedAt = _utc(reviewDateTime ?? DateTime.now());
    final scheduler = fsrs.Scheduler(desiredRetention: desiredRetention);
    return _apply(scheduler, _card(wordId, storedCardJson), rating, reviewedAt);
  }

  FsrsReviewResult _apply(
    fsrs.Scheduler scheduler,
    fsrs.Card card,
    StudyRating rating,
    DateTime reviewedAt,
  ) {
    final fsrsRating = switch (rating) {
      StudyRating.again => fsrs.Rating.again,
      StudyRating.hard => fsrs.Rating.hard,
      StudyRating.good => fsrs.Rating.good,
      StudyRating.easy => fsrs.Rating.easy,
    };
    final reviewedCard = scheduler.reviewCard(
      card,
      fsrsRating,
      reviewDateTime: reviewedAt,
    );
    final cardMap = reviewedCard.card.toMap().cast<String, Object?>();
    final due = DateTime.parse(cardMap['due']! as String);
    return FsrsReviewResult(
      card: cardMap,
      reviewLog: reviewedCard.reviewLog.toMap().cast<String, Object?>(),
      ratingValue: rating.index + 1,
      reviewedAt: reviewedAt,
      intervalLabel: formatFsrsInterval(reviewedAt, due),
    );
  }

  fsrs.Card _card(int wordId, String? storedCardJson) {
    if (storedCardJson == null) return fsrs.Card(cardId: wordId);
    return fsrs.Card.fromMap(
      (jsonDecode(storedCardJson) as Map).cast<String, dynamic>(),
    );
  }

  DateTime _utc(DateTime value) => value.isUtc ? value : value.toUtc();
}

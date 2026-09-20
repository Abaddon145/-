import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/services/fsrs_service.dart';

void main() {
  test('FSRS result can be persisted and restored', () {
    final service = FsrsService();
    final first = service.review(
      wordId: 42,
      storedCardJson: null,
      rating: StudyRating.good,
    );

    expect(first.ratingValue, 3);
    expect(first.card['due'], isNotNull);

    final second = service.review(
      wordId: 42,
      storedCardJson: jsonEncode(first.card),
      rating: StudyRating.hard,
    );

    expect(second.ratingValue, 2);
    expect(second.reviewLog, isNotEmpty);
  });
}

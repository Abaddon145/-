import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/core/database/app_database.dart';
import 'package:korean_memo/features/study/data/study_repository.dart';
import 'package:korean_memo/features/study/presentation/study_controller.dart';
import 'package:korean_memo/services/fsrs_service.dart';

class _Repository implements StudyRepository {
  final requests = <Completer<Word?>>[];

  @override
  Future<Word?> nextWord() {
    final result = Completer<Word?>();
    requests.add(result);
    return result.future;
  }

  @override
  Future<void> submitRating({
    required Word word,
    required StudyRating rating,
    required Duration duration,
  }) async {}
}

void main() {
  test('study waits for bundled word import before querying the queue', () async {
    final repository = _Repository();
    final ready = Completer<void>();
    final controller = StudyController(repository, beforeLoad: () => ready.future);
    addTearDown(controller.dispose);
    final loading = controller.load();
    expect(repository.requests, isEmpty);
    ready.complete();
    await Future<void>.delayed(Duration.zero);
    expect(repository.requests, hasLength(1));
    repository.requests.single.complete(null);
    await loading;
  });

  test('an older failed request does not overwrite a newer loaded queue', () async {
    final repository = _Repository();
    final controller = StudyController(repository);
    addTearDown(controller.dispose);
    var latest = const StudyUiState();
    final removeListener = controller.addListener((value) => latest = value);
    addTearDown(removeListener);
    final first = controller.load();
    await Future<void>.delayed(Duration.zero);
    final second = controller.load();
    await Future<void>.delayed(Duration.zero);
    repository.requests[1].complete(null);
    await second;
    repository.requests[0].completeError(StateError('old request'));
    await first;
    expect(latest.error, isNull);
    expect(latest.isComplete, isTrue);
  });

  test('a request completing after disposal is ignored', () async {
    final repository = _Repository();
    final controller = StudyController(repository);
    final loading = controller.load();
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    repository.requests.single.complete(null);
    await expectLater(loading, completes);
  });
}

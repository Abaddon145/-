import 'dart:math';

import '../../../services/fsrs_service.dart';
import 'atlas_models.dart';

enum AtlasQuestionKind { meaning, listen, pictureCloze, spelling }

enum AtlasStepKind { intro, recall }

class AtlasQuizWord {
  const AtlasQuizWord({
    required this.id,
    required this.headword,
    required this.meaning,
    required this.pos,
    required this.cefr,
    required this.hasImage,
    required this.example,
    this.stability = 0,
    this.atlasId = '',
  });

  final int id;
  final String headword;
  final String meaning;
  final String pos;
  final String cefr;
  final bool hasImage;
  final String example;
  final double stability;
  final String atlasId;
}

class AtlasStep {
  const AtlasStep({
    required this.wordId,
    required this.phase,
    required this.kind,
    required this.scored,
    this.retry = 0,
  });

  final int wordId;
  final AtlasStepKind phase;
  final AtlasQuestionKind kind;
  final bool scored;
  final int retry;

  AtlasStep copyWith({AtlasQuestionKind? kind, bool? scored, int? retry}) =>
      AtlasStep(
        wordId: wordId,
        phase: phase,
        kind: kind ?? this.kind,
        scored: scored ?? this.scored,
        retry: retry ?? this.retry,
      );
}

class AtlasQuestion {
  const AtlasQuestion({
    required this.prompt,
    required this.answer,
    required this.options,
    required this.kind,
  });

  final String prompt;
  final String answer;
  final List<String> options;
  final AtlasQuestionKind kind;
}

const atlasSlowAnswer = Duration(seconds: 12);
const atlasFastSpelling = Duration(seconds: 8);
const atlasRetryGap = 3;
const atlasMaxRetries = 2;
const atlasNewGroupSize = 5;

StudyRating capRatingForHint(StudyRating rating, {required bool usedHint}) {
  if (!usedHint) return rating;
  return rating.index > StudyRating.hard.index ? StudyRating.hard : rating;
}

StudyRating gradeAtlasAnswer({
  required bool correct,
  required Duration elapsed,
  required bool usedHint,
  required AtlasQuestionKind kind,
}) {
  if (!correct) return StudyRating.again;
  if (usedHint) return StudyRating.hard;
  if (elapsed >= atlasSlowAnswer) return StudyRating.hard;
  if (kind == AtlasQuestionKind.spelling && elapsed <= atlasFastSpelling) {
    return StudyRating.easy;
  }
  return StudyRating.good;
}

int cefrDistance(String a, String b) {
  final left = atlasCefrLevels.indexOf(a.toUpperCase());
  final right = atlasCefrLevels.indexOf(b.toUpperCase());
  if (left < 0 || right < 0) return 3;
  return (left - right).abs();
}

AtlasQuestionKind reviewKindFor(AtlasQuizWord word) {
  if (word.stability >= masteredStabilityDays) {
    return AtlasQuestionKind.spelling;
  }
  if (word.stability >= 4) return AtlasQuestionKind.listen;
  if (word.hasImage && word.example.isNotEmpty) {
    return AtlasQuestionKind.pictureCloze;
  }
  return AtlasQuestionKind.meaning;
}

AtlasQuestionKind rotateKind(
  AtlasQuestionKind current, {
  required bool hasImage,
}) {
  const order = [
    AtlasQuestionKind.meaning,
    AtlasQuestionKind.listen,
    AtlasQuestionKind.pictureCloze,
    AtlasQuestionKind.spelling,
  ];
  for (var hop = 1; hop <= order.length; hop++) {
    final next = order[(order.indexOf(current) + hop) % order.length];
    if (next == AtlasQuestionKind.pictureCloze && !hasImage) continue;
    return next;
  }
  return AtlasQuestionKind.meaning;
}

List<AtlasStep> buildAtlasJourney({
  required List<AtlasQuizWord> reviews,
  required List<AtlasQuizWord> fresh,
  int groupSize = atlasNewGroupSize,
  Random? random,
}) {
  final rng = random ?? Random();
  final steps = <AtlasStep>[
    for (final word in reviews)
      AtlasStep(
        wordId: word.id,
        phase: AtlasStepKind.recall,
        kind: reviewKindFor(word),
        scored: true,
      ),
  ];
  for (var offset = 0; offset < fresh.length; offset += groupSize) {
    final group = fresh.skip(offset).take(groupSize).toList();
    steps.addAll([
      for (final word in group)
        AtlasStep(
          wordId: word.id,
          phase: AtlasStepKind.intro,
          kind: AtlasQuestionKind.meaning,
          scored: false,
        ),
    ]);
    final shuffled = [...group]..shuffle(rng);
    steps.addAll([
      for (final word in shuffled)
        AtlasStep(
          wordId: word.id,
          phase: AtlasStepKind.recall,
          kind: word.hasImage && word.example.isNotEmpty
              ? AtlasQuestionKind.pictureCloze
              : AtlasQuestionKind.meaning,
          scored: true,
        ),
    ]);
  }
  return steps;
}

class AtlasSession {
  AtlasSession({
    required this.steps,
    this.cursor = 0,
    Set<int>? scoredIds,
    Map<int, int>? retries,
  }) : scoredIds = scoredIds ?? <int>{},
       retries = retries ?? <int, int>{};

  final List<AtlasStep> steps;
  int cursor;
  final Set<int> scoredIds;
  final Map<int, int> retries;

  bool get isComplete => cursor >= steps.length;
  AtlasStep? get current => isComplete ? null : steps[cursor];

  bool writesScore(AtlasStep step) =>
      step.scored &&
      step.phase == AtlasStepKind.recall &&
      !scoredIds.contains(step.wordId);

  /// Records the answer. A wrong recall is queued [atlasRetryGap] items later,
  /// at most [atlasMaxRetries] times, and those retries do not score.
  void answer({required bool correct, required bool hasImage}) {
    final step = current;
    if (step == null) return;
    if (writesScore(step)) scoredIds.add(step.wordId);
    final used = retries[step.wordId] ?? step.retry;
    if (!correct &&
        step.phase == AtlasStepKind.recall &&
        used < atlasMaxRetries) {
      retries[step.wordId] = used + 1;
      final insertAt = min(cursor + 1 + atlasRetryGap, steps.length);
      steps.insert(
        insertAt,
        AtlasStep(
          wordId: step.wordId,
          phase: AtlasStepKind.recall,
          kind: rotateKind(step.kind, hasImage: hasImage),
          scored: false,
          retry: used + 1,
        ),
      );
    }
    cursor += 1;
  }
}

int spellingDistance(String a, String b) {
  final left = a.toLowerCase();
  final right = b.toLowerCase();
  if (left == right) return 0;
  var prefix = 0;
  while (prefix < left.length &&
      prefix < right.length &&
      left[prefix] == right[prefix]) {
    prefix++;
  }
  return (left.length - prefix) + (right.length - prefix);
}

List<AtlasQuizWord> meaningDistractors({
  required AtlasQuizWord target,
  required List<AtlasQuizWord> pool,
  int count = 3,
}) {
  final ranked =
      [
        for (final word in pool)
          if (word.id != target.id && word.meaning.trim().isNotEmpty) word,
      ]..sort((a, b) {
        final posA = a.pos == target.pos ? 0 : 1;
        final posB = b.pos == target.pos ? 0 : 1;
        final level = cefrDistance(
          a.cefr,
          target.cefr,
        ).compareTo(cefrDistance(b.cefr, target.cefr));
        if (posA != posB) return posA.compareTo(posB);
        return level;
      });
  final picked = <AtlasQuizWord>[];
  final seen = <String>{target.meaning.trim()};
  for (final word in ranked) {
    if (!seen.add(word.meaning.trim())) continue;
    picked.add(word);
    if (picked.length == count) break;
  }
  return picked;
}

List<AtlasQuizWord> spellingDistractors({
  required AtlasQuizWord target,
  required List<AtlasQuizWord> pool,
  int count = 3,
}) {
  final ranked =
      [
        for (final word in pool)
          if (word.id != target.id && word.headword.trim().isNotEmpty) word,
      ]..sort(
        (a, b) => spellingDistance(
          a.headword,
          target.headword,
        ).compareTo(spellingDistance(b.headword, target.headword)),
      );
  return ranked.take(count).toList();
}

AtlasQuestion buildAtlasQuestion({
  required AtlasQuizWord word,
  required AtlasQuestionKind kind,
  required List<AtlasQuizWord> pool,
  Random? random,
}) {
  final rng = random ?? Random();
  List<String> optionsOf(List<String> values, String answer) {
    final unique = <String>{answer, ...values.where((item) => item != answer)};
    final list = unique.toList()..shuffle(rng);
    return list;
  }

  switch (kind) {
    case AtlasQuestionKind.listen:
      final distractors = spellingDistractors(
        target: word,
        pool: pool,
      ).map((item) => item.headword).toList();
      return AtlasQuestion(
        prompt: '听发音，选出单词',
        answer: word.headword,
        options: optionsOf(distractors, word.headword),
        kind: kind,
      );
    case AtlasQuestionKind.pictureCloze:
      final sentence = word.example.trim().isEmpty
          ? word.meaning
          : word.example.replaceAll(
              RegExp(RegExp.escape(word.headword), caseSensitive: false),
              '＿＿＿',
            );
      final distractors = spellingDistractors(
        target: word,
        pool: pool,
      ).map((item) => item.headword).toList();
      return AtlasQuestion(
        prompt: sentence,
        answer: word.headword,
        options: optionsOf(distractors, word.headword),
        kind: word.hasImage ? kind : AtlasQuestionKind.meaning,
      );
    case AtlasQuestionKind.spelling:
      return AtlasQuestion(
        prompt: word.meaning,
        answer: word.headword,
        options: const [],
        kind: kind,
      );
    case AtlasQuestionKind.meaning:
      final distractors = meaningDistractors(
        target: word,
        pool: pool,
      ).map((item) => item.meaning).toList();
      return AtlasQuestion(
        prompt: word.headword,
        answer: word.meaning,
        options: optionsOf(distractors, word.meaning),
        kind: kind,
      );
  }
}

String revealSpellingHint(String answer, String shown) {
  final target = answer.trim();
  if (shown.length >= target.length) return target;
  return target.substring(0, shown.length + 1);
}

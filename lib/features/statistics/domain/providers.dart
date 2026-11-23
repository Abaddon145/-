import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/time/local_day.dart';
import '../../study/domain/providers.dart';
import '../data/language_comparison.dart';

/// `active` follows the home language. `ko`, `en`, and `all` are explicit.
final statisticsScopeProvider = StateProvider<String>((ref) => 'active');

String statisticsLanguageOf(Ref ref) {
  final scope = ref.watch(statisticsScopeProvider);
  if (scope == 'ko' || scope == 'en') return scope;
  return ref.watch(activeLanguageProvider);
}

bool statisticsCombine(Ref ref) => ref.watch(statisticsScopeProvider) == 'all';

final recentStatisticsProvider =
    FutureProvider.autoDispose<List<DailyStatisticsSummary>>((ref) {
      ref.watch(localDayProvider);
      return ref
          .watch(databaseProvider)
          .loadRecentStatistics(
            DateTime.now(),
            language: statisticsLanguageOf(ref),
            combineLanguages: statisticsCombine(ref),
          );
    });

final languageComparisonProvider =
    FutureProvider.autoDispose<LanguageComparison>((ref) async {
      ref.watch(localDayProvider);
      final db = ref.watch(databaseProvider);
      final now = DateTime.now();
      return LanguageComparison(
        mastery: await db.masteryByLanguage(),
        days: {
          'ko': await db.loadRecentStatistics(now, language: 'ko'),
          'en': await db.loadRecentStatistics(now, language: 'en'),
        },
      );
    });

final learningOverviewProvider = FutureProvider.autoDispose<Map<String, int>>((
  ref,
) async {
  final db = ref.watch(databaseProvider);
  final language = statisticsCombine(ref) ? null : statisticsLanguageOf(ref);
  final cardQuery = db.select(db.studyCards);
  final wordQuery = db.select(db.words);
  if (language != null) {
    cardQuery.where((row) => row.language.equals(language));
    wordQuery.where((row) => row.language.equals(language));
  }
  final cards = await cardQuery.get();
  final words = await wordQuery.get();
  final wordIds = words.map((word) => word.id).toSet();
  final states = await (db.select(
    db.appSettings,
  )..where((r) => r.key.like('word_status:%'))).get();
  return {
    'learned': cards.length,
    'known': states.where((r) {
      final id = int.tryParse(r.key.substring(12));
      return r.value == 'known' && wordIds.contains(id);
    }).length,
    'suspended': states.where((r) {
      final id = int.tryParse(r.key.substring(12));
      return r.value == 'suspended' && wordIds.contains(id);
    }).length,
  };
});
final reviewForecastProvider =
    FutureProvider.autoDispose<List<Map<String, Object?>>>((ref) async {
      ref.watch(localDayProvider);
      final db = ref.watch(databaseProvider);
      final now = DateTime.now();
      if (!statisticsCombine(ref)) {
        return db.reviewForecast(now, statisticsLanguageOf(ref));
      }
      final korean = await db.reviewForecast(now, 'ko');
      final english = await db.reviewForecast(now, 'en');
      return [
        for (var i = 0; i < korean.length; i++)
          {
            'day': korean[i]['day'],
            'count': (korean[i]['count'] as int) + (english[i]['count'] as int),
          },
      ];
    });
final monthStatisticsProvider =
    FutureProvider.autoDispose<List<DailyStatisticsSummary>>((ref) {
      ref.watch(localDayProvider);
      return ref
          .watch(databaseProvider)
          .loadRecentStatistics(
            DateTime.now(),
            days: 30,
            language: statisticsLanguageOf(ref),
            combineLanguages: statisticsCombine(ref),
          );
    });
final objectiveStatisticsProvider =
    FutureProvider.autoDispose<Map<String, Map<String, int>>>((ref) async {
      ref.watch(recentStatisticsProvider);
      final db = ref.watch(databaseProvider);
      if (statisticsCombine(ref)) {
        final korean = await _objectiveRows(db, 'ko');
        final english = await _objectiveRows(db, 'en');
        return {
          for (final key in {...korean.keys, ...english.keys})
            key: {
              'total':
                  (korean[key]?['total'] ?? 0) + (english[key]?['total'] ?? 0),
              'correct':
                  (korean[key]?['correct'] ?? 0) +
                  (english[key]?['correct'] ?? 0),
            },
        };
      }
      return _objectiveRows(db, statisticsLanguageOf(ref));
    });

final statisticsCheckinsProvider = FutureProvider.autoDispose<CheckinSummary>((
  ref,
) async {
  ref.watch(localDayProvider);
  final db = ref.watch(databaseProvider);
  final now = DateTime.now();
  if (!statisticsCombine(ref)) {
    return db.loadCheckins(now, statisticsLanguageOf(ref));
  }
  final korean = await db.loadCheckins(now, 'ko');
  final english = await db.loadCheckins(now, 'en');
  return _mergedCheckins({...korean.days, ...english.days}, now);
});

Future<Map<String, Map<String, int>>> _objectiveRows(
  AppDatabase db,
  String language,
) async {
  final prefix = 'objective:$language:';
  final rows = await (db.select(
    db.appSettings,
  )..where((r) => r.key.like('$prefix%'))).get();
  return {
    for (final row in rows)
      row.key.substring(prefix.length): Map<String, int>.from(
        jsonDecode(row.value) as Map,
      ),
  };
}

CheckinSummary _mergedCheckins(Set<String> days, DateTime now) {
  var cursor = DateTime(now.year, now.month, now.day);
  if (!days.contains(dayKey(cursor))) {
    cursor = cursor.subtract(const Duration(days: 1));
  }
  var streak = 0;
  while (days.contains(dayKey(cursor))) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  var longest = 0, current = 0;
  DateTime? previous;
  final sorted = days.toList()..sort();
  for (final day in sorted) {
    final date = DateTime.parse('${day}T00:00:00Z');
    current = previous != null && date.difference(previous).inDays == 1
        ? current + 1
        : 1;
    if (current > longest) longest = current;
    previous = date;
  }
  return CheckinSummary(days, streak, longest);
}

import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/time/local_day.dart';
import '../../study/domain/providers.dart';

final recentStatisticsProvider =
    FutureProvider.autoDispose<List<DailyStatisticsSummary>>((ref) {
      ref.watch(localDayProvider);
      return ref
          .watch(databaseProvider)
          .loadRecentStatistics(
            DateTime.now(),
            language: ref.watch(activeLanguageProvider),
          );
    });

final learningOverviewProvider = FutureProvider.autoDispose<Map<String, int>>((
  ref,
) async {
  final db = ref.watch(databaseProvider);
  final language = ref.watch(activeLanguageProvider);
  final cards = await (db.select(
    db.studyCards,
  )..where((row) => row.language.equals(language))).get();
  final words = await (db.select(
    db.words,
  )..where((row) => row.language.equals(language))).get();
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
    FutureProvider.autoDispose<List<Map<String, Object?>>>((ref) {
      ref.watch(localDayProvider);
      return ref
          .watch(databaseProvider)
          .reviewForecast(DateTime.now(), ref.watch(activeLanguageProvider));
    });
final monthStatisticsProvider =
    FutureProvider.autoDispose<List<DailyStatisticsSummary>>((ref) {
      ref.watch(localDayProvider);
      return ref
          .watch(databaseProvider)
          .loadRecentStatistics(
            DateTime.now(),
            days: 30,
            language: ref.watch(activeLanguageProvider),
          );
    });
final objectiveStatisticsProvider =
    FutureProvider.autoDispose<Map<String, Map<String, int>>>((ref) async {
      ref.watch(recentStatisticsProvider);
      final db = ref.watch(databaseProvider);
      final language = ref.watch(activeLanguageProvider);
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
    });

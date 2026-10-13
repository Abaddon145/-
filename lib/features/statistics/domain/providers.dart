import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/time/local_day.dart';
import '../../study/domain/providers.dart';

final recentStatisticsProvider = FutureProvider.autoDispose<List<DailyStatisticsSummary>>((ref) {
  ref.watch(localDayProvider);
  return ref.watch(databaseProvider).loadRecentStatistics(DateTime.now());
});

final learningOverviewProvider=FutureProvider.autoDispose<Map<String,int>>((ref)async {
  final db=ref.watch(databaseProvider);
  final cards=await db.select(db.studyCards).get();
  final states=await (db.select(db.appSettings)..where((r)=>r.key.like('word_status:%'))).get();
  return {'learned':cards.length,'known':states.where((r)=>r.value=='known').length,
    'suspended':states.where((r)=>r.value=='suspended').length};
});
final reviewForecastProvider=FutureProvider.autoDispose<List<Map<String,Object?>>>((ref){
  ref.watch(localDayProvider);return ref.watch(databaseProvider).reviewForecast(DateTime.now());
});
final monthStatisticsProvider=FutureProvider.autoDispose<List<DailyStatisticsSummary>>((ref){
  ref.watch(localDayProvider);return ref.watch(databaseProvider).loadRecentStatistics(DateTime.now(),days:30);
});
final objectiveStatisticsProvider=FutureProvider.autoDispose<Map<String,Map<String,int>>>((ref)async {
  ref.watch(recentStatisticsProvider);
  final db=ref.watch(databaseProvider);
  final rows=await (db.select(db.appSettings)..where((r)=>r.key.like('objective:%'))).get();
  return {for(final row in rows) row.key.substring(10): Map<String,int>.from(jsonDecode(row.value) as Map)};
});

import 'dart:convert';

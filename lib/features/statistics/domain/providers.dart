import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/time/local_day.dart';
import '../../study/domain/providers.dart';

final recentStatisticsProvider = FutureProvider.autoDispose<List<DailyStatisticsSummary>>((ref) {
  ref.watch(localDayProvider);
  return ref.watch(databaseProvider).loadRecentStatistics(DateTime.now());
});


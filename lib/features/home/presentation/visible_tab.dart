import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/domain/providers.dart';
import '../../statistics/domain/providers.dart';
import '../../study/domain/providers.dart';

/// Bottom-nav index of the page the learner is looking at.
final visibleTabProvider = StateProvider<int>((ref) => 0);

void refreshVisibleTab(WidgetRef ref, int index) {
  switch (index) {
    case 0:
      ref.invalidate(homeCountsProvider);
      ref.invalidate(dailyPlanProgressProvider);
      ref.invalidate(checkinsProvider);
    case 1:
      ref.invalidate(libraryWordsProvider);
      ref.invalidate(libraryCountProvider);
    case 3:
      ref.invalidate(recentStatisticsProvider);
      ref.invalidate(monthStatisticsProvider);
      ref.invalidate(reviewForecastProvider);
      ref.invalidate(learningOverviewProvider);
      ref.invalidate(objectiveStatisticsProvider);
  }
}

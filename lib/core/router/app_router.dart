import 'package:go_router/go_router.dart';
import '../../features/home/presentation/app_navigation_shell.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/import/presentation/import_page.dart';
import '../../features/library/presentation/library_page.dart';
import '../../features/settings/presentation/appearance_page.dart';
import '../../features/settings/presentation/daily_plan_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/statistics/presentation/statistics_page.dart';
import '../../features/study/presentation/study_page.dart';

final appRouter = GoRouter(
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppNavigationShell(navigationShell: shell),
      branches: [
        StatefulShellBranch(routes: [GoRoute(path: '/', builder: (context, state) => const HomePage())]),
        StatefulShellBranch(routes: [GoRoute(path: '/library', builder: (context, state) => const LibraryPage())]),
        StatefulShellBranch(routes: [GoRoute(path: '/study', builder: (context, state) => const StudyPage())]),
        StatefulShellBranch(routes: [GoRoute(path: '/statistics', builder: (context, state) => const StatisticsPage())]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/settings', builder: (context, state) => const SettingsPage(), routes: [
            GoRoute(path: 'daily-plan', builder: (context, state) => const DailyPlanPage()),
            GoRoute(path: 'appearance', builder: (context, state) => const AppearancePage()),
          ]),
        ]),
      ],
    ),
    GoRoute(path: '/import', builder: (context, state) => const ImportPage()),
  ],
);

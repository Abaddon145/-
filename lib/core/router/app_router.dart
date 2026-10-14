import 'package:flutter/material.dart';
import '../theme/app_backdrop.dart';
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
import '../../features/statistics/presentation/checkin_page.dart';
import '../../features/settings/presentation/reading_page.dart';
import '../../features/sync/presentation/cloud_sync_page.dart';

Page<void> appPage(GoRouterState state, Widget child, {bool backdrop = false}) =>
    NoTransitionPage<void>(key: state.pageKey,
      child: backdrop ? AppBackdrop(child: child) : RepaintBoundary(child: child));

final appRouter = GoRouter(
  routes: [
    StatefulShellRoute.indexedStack(
      pageBuilder: (context, state, shell) => appPage(state, AppNavigationShell(navigationShell: shell), backdrop: true),
      branches: [
        StatefulShellBranch(routes: [GoRoute(path: '/', pageBuilder: (context, state) => appPage(state, const HomePage(), backdrop: false))]),
        StatefulShellBranch(routes: [GoRoute(path: '/library', pageBuilder: (context, state) => appPage(state, const LibraryPage(), backdrop: false))]),
        StatefulShellBranch(routes: [GoRoute(path: '/study', pageBuilder: (context, state) => appPage(state, const StudyPage(), backdrop: false))]),
        StatefulShellBranch(routes: [GoRoute(path: '/statistics', pageBuilder: (context, state) => appPage(state, const StatisticsPage(), backdrop: false))]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/settings', pageBuilder: (context, state) => appPage(state, const SettingsPage(), backdrop: false), routes: [
            GoRoute(path: 'daily-plan', pageBuilder: (context, state) => appPage(state, const DailyPlanPage(), backdrop: true)),
            GoRoute(path: 'appearance', pageBuilder: (context, state) => appPage(state, const AppearancePage(), backdrop: true)),
            GoRoute(path: 'reading', pageBuilder: (context, state) => appPage(state, const ReadingPage(), backdrop: true)),
            GoRoute(path: 'cloud', pageBuilder: (context, state) => appPage(state, const CloudSyncPage(), backdrop: true)),
          ]),
        ]),
      ],
    ),
    GoRoute(path: '/checkin', pageBuilder: (context, state) => appPage(state, const CheckinPage(), backdrop: true)),
    GoRoute(path: '/import', pageBuilder: (context, state) => appPage(state, const ImportPage(), backdrop: true)),
  ],
);

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/reading_preferences.dart';
import '../../study/domain/providers.dart';
import '../../sync/presentation/cloud_sync_controller.dart';

class AppNavigationShell extends ConsumerWidget {
  const AppNavigationShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active=navigationShell.currentIndex==2;
    final cloud = ref.watch(cloudSyncProvider);
    final attention = cloud.needsChoice || cloud.failed || cloud.pendingLocal || cloud.cloudChanged;
    WidgetsBinding.instance.addPostFrameCallback((_){if(context.mounted&&ref.read(studyVisibleProvider)!=active){ref.read(studyVisibleProvider.notifier).state=active;}});
    return Scaffold(
    body: navigationShell,
    bottomNavigationBar: active&&ref.watch(readingProvider).valueOrNull?.focus==true?null:NavigationBar(
      selectedIndex: navigationShell.currentIndex,
      onDestinationSelected: (index) => navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex),
      destinations: [
        const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: '首页'),
        const NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: '词库'),
        const NavigationDestination(icon: Icon(Icons.school_outlined), selectedIcon: Icon(Icons.school), label: '学习'),
        const NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: '统计'),
        NavigationDestination(icon: Badge(isLabelVisible: attention, child: const Icon(Icons.settings_outlined)), selectedIcon: Badge(isLabelVisible: attention, child: const Icon(Icons.settings)), label: '设置'),
      ],
    ),
  );
  }
}

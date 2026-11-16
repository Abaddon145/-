import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/reading_preferences.dart';
import '../../../core/theme/app_motion.dart';
import '../../study/domain/providers.dart';
import 'visible_tab.dart';

class AppNavigationShell extends ConsumerWidget {
  const AppNavigationShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = navigationShell.currentIndex == 2;
    final index = navigationShell.currentIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      if (ref.read(studyVisibleProvider) != active) {
        ref.read(studyVisibleProvider.notifier).state = active;
      }
      if (ref.read(visibleTabProvider) != index) {
        ref.read(visibleTabProvider.notifier).state = index;
      }
    });
    final focus = ref.watch(readingProvider).valueOrNull?.focus == true;
    final hideNav = active && (focus || ref.watch(studyHasCardProvider));
    final motion = AppMotion.duration(context, 200);
    return Scaffold(
      body: Builder(
        builder: (context) {
          if (!hideNav) return navigationShell;
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(
              padding: media.padding.copyWith(bottom: media.viewPadding.bottom),
            ),
            child: navigationShell,
          );
        },
      ),
      bottomNavigationBar: _CollapsingNav(
        visible: !hideNav,
        duration: motion,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: .4),
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(
                  context,
                ).colorScheme.shadow.withValues(alpha: .05),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: NavigationBar(
            animationDuration: AppMotion.duration(context, 240),
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: (index) {
              navigationShell.goBranch(
                index,
                initialLocation: index == navigationShell.currentIndex,
              );
              ref.read(visibleTabProvider.notifier).state = index;
              refreshVisibleTab(ref, index);
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: '首页',
              ),
              NavigationDestination(
                icon: Icon(Icons.menu_book_outlined),
                selectedIcon: Icon(Icons.menu_book),
                label: '词库',
              ),
              NavigationDestination(
                icon: Icon(Icons.school_outlined),
                selectedIcon: Icon(Icons.school),
                label: '学习',
              ),
              NavigationDestination(
                icon: Icon(Icons.bar_chart_outlined),
                selectedIcon: Icon(Icons.bar_chart),
                label: '统计',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: '设置',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollapsingNav extends StatefulWidget {
  const _CollapsingNav({
    required this.visible,
    required this.duration,
    required this.child,
  });
  final bool visible;
  final Duration duration;
  final Widget child;

  @override
  State<_CollapsingNav> createState() => _CollapsingNavState();
}

class _CollapsingNavState extends State<_CollapsingNav>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: widget.visible ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant _CollapsingNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.duration;
    if (widget.duration == Duration.zero) {
      _controller.value = widget.visible ? 1 : 0;
      return;
    }
    if (widget.visible) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: _controller,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: _controller,
        child: IgnorePointer(ignoring: !widget.visible, child: widget.child),
      ),
    );
  }
}

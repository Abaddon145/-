import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/time/local_day.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/appearance_settings.dart';
import 'features/sync/presentation/cloud_sync_observer.dart';

class KoreanMemoApp extends ConsumerWidget {
  const KoreanMemoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceProvider).valueOrNull;
    final preset = AppTheme.preset(appearance?.styleId ?? 'porcelain');
    return MaterialApp.router(
      title: 'KoreanMemo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.forPreset(preset),
      themeMode: preset.dark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: appRouter,
      builder: (context, child) => CloudSyncObserver(
        child: LocalDayObserver(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}

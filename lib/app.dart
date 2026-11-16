import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/time/local_day.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/appearance_settings.dart';
import 'features/ai/domain/ai_providers.dart';

class KoreanMemoApp extends ConsumerWidget {
  const KoreanMemoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(aiApiKeyProvider);
    final appearance = ref.watch(appearanceProvider).valueOrNull;
    final saved = AppTheme.preset(appearance?.styleId ?? 'porcelain');
    final follow = appearance?.followSystem ?? false;
    final light = saved.dark ? AppTheme.presets.first : saved;
    final dark = AppTheme.preset('night');
    return MaterialApp.router(
      title: '词忆',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: AppTheme.forPreset(follow ? light : saved),
      darkTheme: AppTheme.forPreset(
        follow ? dark : (saved.dark ? saved : dark),
      ),
      themeMode: follow
          ? ThemeMode.system
          : (saved.dark ? ThemeMode.dark : ThemeMode.light),
      routerConfig: appRouter,
      builder: (context, child) =>
          LocalDayObserver(child: child ?? const SizedBox.shrink()),
    );
  }
}

import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/time/local_day.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/appearance_settings.dart';

class KoreanMemoApp extends ConsumerWidget {
  const KoreanMemoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceProvider).valueOrNull;
    final preset = AppTheme.preset(appearance?.styleId ?? 'porcelain');
    final background = appearance?.backgroundBytes;
    return MaterialApp.router(
      title: 'KoreanMemo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.forPreset(preset),
      themeMode: preset.dark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: appRouter,
      builder: (context, child) => LocalDayObserver(child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [preset.start, preset.end],
              ),
            ),
          ),
          if (background != null) ...[
            ClipRect(child:Transform.scale(scale:appearance?.zoom??1,child:ImageFiltered(
              imageFilter:ui.ImageFilter.blur(sigmaX:appearance?.blur??0,sigmaY:appearance?.blur??0),child:Image.memory(
              background,
              fit: BoxFit.cover,
              alignment:Alignment(appearance?.x??0,appearance?.y??0),
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            )))),
            ColoredBox(
              color: preset.dark
                  ? Colors.black.withValues(alpha: appearance?.opacity??.68)
                  : Colors.white.withValues(alpha: appearance?.opacity??.72),
            ),
          ],
          child ?? const SizedBox.shrink(),
        ],
      )),
    );
  }
}

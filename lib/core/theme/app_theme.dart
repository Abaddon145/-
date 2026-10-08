import 'package:flutter/material.dart';

class AppearancePreset {
  const AppearancePreset({
    required this.id,
    required this.name,
    required this.description,
    required this.seed,
    required this.start,
    required this.end,
    this.dark = false,
  });

  final String id;
  final String name;
  final String description;
  final Color seed;
  final Color start;
  final Color end;
  final bool dark;
}

abstract final class AppTheme {
  static const presets = <AppearancePreset>[
    AppearancePreset(
      id: 'porcelain',
      name: '云白',
      description: '柔和的蓝紫色',
      seed: Color(0xFF6267D8),
      start: Color(0xFFF8F8FF),
      end: Color(0xFFE9EEFF),
    ),
    AppearancePreset(
      id: 'forest',
      name: '青森',
      description: '安静的薄荷绿',
      seed: Color(0xFF277568),
      start: Color(0xFFF3FBF6),
      end: Color(0xFFDDEFE9),
    ),
    AppearancePreset(
      id: 'dusk',
      name: '暮霞',
      description: '温暖的珊瑚粉',
      seed: Color(0xFFAD586A),
      start: Color(0xFFFFF7F2),
      end: Color(0xFFF6E5EF),
    ),
    AppearancePreset(
      id: 'paper',
      name: '纸笺',
      description: '书页般的暖白与墨棕',
      seed: Color(0xFF78604C),
      start: Color(0xFFFBF8F0),
      end: Color(0xFFEDE4D5),
    ),
    AppearancePreset(
      id: 'ocean',
      name: '海盐',
      description: '清透的冰蓝色',
      seed: Color(0xFF246C93),
      start: Color(0xFFF3FAFF),
      end: Color(0xFFDCEEF7),
    ),
    AppearancePreset(
      id: 'night',
      name: '深夜',
      description: '沉静的深蓝色',
      seed: Color(0xFF91A3FF),
      start: Color(0xFF11182E),
      end: Color(0xFF293358),
      dark: true,
    ),
  ];

  static AppearancePreset preset(String id) =>
      presets.where((item) => item.id == id).firstOrNull ?? presets.first;

  static ThemeData forPreset(AppearancePreset preset) {
    final scheme = ColorScheme.fromSeed(
      seedColor: preset.seed,
      brightness: preset.dark ? Brightness.dark : Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      visualDensity: VisualDensity.standard,
      textTheme: Typography.material2021().black.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.55),
        thickness: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.primary.withValues(alpha: 0.12),
        linearMinHeight: 6,
        borderRadius: BorderRadius.circular(12),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface.withValues(alpha: 0.94),
        height: 76,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700 : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? scheme.primary : scheme.onSurfaceVariant,
        )),
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface.withValues(alpha: 0.92),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.42)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface.withValues(alpha: 0.94),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }
}

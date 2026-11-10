import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_theme.dart';
import 'appearance_settings.dart';

/// Every navigator surface paints its own opaque backdrop, preventing underlying
/// pages from showing through transparent scaffolds during navigation.
class AppBackdrop extends ConsumerWidget {
  const AppBackdrop({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceProvider).valueOrNull;
    final preset = AppTheme.preset(appearance?.styleId ?? 'porcelain');
    final background = appearance?.backgroundBytes;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final decodeWidth = (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(1, 1600).toInt();
    return Stack(fit: StackFit.expand, children: [
      RepaintBoundary(child: Stack(fit: StackFit.expand, children: [
        DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: _backdropColors(preset, dark),
        ))),
        if (background != null) ...[
          ClipRect(child: Transform.scale(scale: appearance?.zoom ?? 1,
            child: ImageFiltered(imageFilter: ui.ImageFilter.blur(
              sigmaX: appearance?.blur ?? 0, sigmaY: appearance?.blur ?? 0),
              child: Image.memory(background, cacheWidth: decodeWidth,
                fit: BoxFit.cover, alignment: Alignment(appearance?.x ?? 0, appearance?.y ?? 0),
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          )),
          ColoredBox(color: (dark ? Colors.black : Colors.white)
            .withValues(alpha: appearance?.opacity ?? (dark ? .68 : .72))),
        ],
      ])),
      RepaintBoundary(child: child),
    ]);
  }
}

List<Color> _backdropColors(AppearancePreset preset, bool dark) {
  if (dark == preset.dark) return [preset.start, preset.end];
  if (dark) {
    return [
      Color.alphaBlend(preset.seed.withValues(alpha: .42), const Color(0xFF12141C)),
      Color.alphaBlend(preset.seed.withValues(alpha: .22), const Color(0xFF1B2030)),
    ];
  }
  return [
    Color.alphaBlend(preset.seed.withValues(alpha: .08), const Color(0xFFF7F8FC)),
    Color.alphaBlend(preset.seed.withValues(alpha: .16), const Color(0xFFE7EBF6)),
  ];
}

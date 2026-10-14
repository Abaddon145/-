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
    final decodeWidth = (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(1, 1600).toInt();
    return Stack(fit: StackFit.expand, children: [
      RepaintBoundary(child: Stack(fit: StackFit.expand, children: [
        DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [preset.start, preset.end],
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
          ColoredBox(color: (preset.dark ? Colors.black : Colors.white)
            .withValues(alpha: appearance?.opacity ?? (preset.dark ? .68 : .72))),
        ],
      ])),
      RepaintBoundary(child: child),
    ]);
  }
}

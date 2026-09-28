import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/study/domain/providers.dart';
import 'app_theme.dart';

class AppearanceSettings {
  const AppearanceSettings({required this.styleId, this.backgroundBytes});
  static const styleKey = 'appearance_style';
  static const backgroundKey = 'appearance_background_base64';

  final String styleId;
  final Uint8List? backgroundBytes;

  bool get hasBackground => backgroundBytes != null;
}

final appearanceProvider = FutureProvider<AppearanceSettings>((ref) async {
  final database = ref.watch(databaseProvider);
  final savedStyle = await database.loadSetting(AppearanceSettings.styleKey);
  final styleId = AppTheme.presets.any((style) => style.id == savedStyle)
      ? savedStyle!
      : AppTheme.presets.first.id;
  final encoded = await database.loadSetting(AppearanceSettings.backgroundKey);
  Uint8List? bytes;
  if (encoded != null) {
    try {
      bytes = base64Decode(encoded);
    } on FormatException {
      bytes = null;
    }
  }
  return AppearanceSettings(styleId: styleId, backgroundBytes: bytes);
});

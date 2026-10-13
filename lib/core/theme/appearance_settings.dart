import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/study/domain/providers.dart';
import 'app_theme.dart';

class AppearanceSettings {
  const AppearanceSettings({required this.styleId, this.backgroundBytes,this.blur=0,this.opacity=.72,this.x=0,this.y=0,this.zoom=1});
  static const styleKey = 'appearance_style';
  static const backgroundKey = 'appearance_background_base64';

  final String styleId;
  final Uint8List? backgroundBytes;
  final double blur,opacity,x,y,zoom;

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
  Future<double> number(String key,double fallback)async=>double.tryParse(await database.loadSetting(key)??'')??fallback;
  return AppearanceSettings(styleId: styleId, backgroundBytes: bytes,
    blur:(await number('background_blur',0)).clamp(0,12),opacity:(await number('background_opacity',.72)).clamp(.2,.9),
    x:(await number('background_x',0)).clamp(-1,1),y:(await number('background_y',0)).clamp(-1,1),zoom:(await number('background_zoom',1)).clamp(1,2));
});

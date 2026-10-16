import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/core/theme/app_theme.dart';

// Read the font's real Unicode cmap, not a separately maintained character list.
Set<int> fontCodepoints(ByteData bytes) {
  int u16(int offset) => bytes.getUint16(offset, Endian.big);
  int u32(int offset) => bytes.getUint32(offset, Endian.big);
  var cmap = -1;
  for (var i = 0; i < u16(4); i++) {
    final offset = 12 + i * 16;
    if (u32(offset) == 0x636d6170) cmap = u32(offset + 8);
  }
  if (cmap < 0) throw const FormatException('Font has no Unicode cmap');
  final result = <int>{};
  for (var record = 0; record < u16(cmap + 2); record++) {
    final entry = cmap + 4 + record * 8;
    if (u16(entry) != 0 && u16(entry) != 3) continue;
    final table = cmap + u32(entry + 4);
    if (u16(table) == 12) {
      for (var group = 0; group < u32(table + 12); group++) {
        final offset = table + 16 + group * 12;
        for (var cp = u32(offset); cp <= u32(offset + 4); cp++) {
          if (u32(offset + 8) + cp - u32(offset) != 0) result.add(cp);
        }
      }
    } else if (u16(table) == 4) {
      final count = u16(table + 6) ~/ 2;
      final ends = table + 14, starts = ends + count * 2 + 2;
      final deltas = starts + count * 2, offsets = deltas + count * 2;
      for (var segment = 0; segment < count; segment++) {
        final rangeOffset = u16(offsets + segment * 2);
        final first = u16(starts + segment * 2);
        for (var cp = first; cp <= u16(ends + segment * 2); cp++) {
          var glyph = rangeOffset == 0
              ? cp
              : u16(offsets + segment * 2 + rangeOffset + (cp - first) * 2);
          if (rangeOffset != 0 && glyph == 0) continue;
          glyph = (glyph + u16(deltas + segment * 2)) & 0xffff;
          if (glyph != 0) result.add(cp);
        }
      }
    }
  }
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Set<int> glyphs;
  setUpAll(() {
    glyphs = fontCodepoints(
      ByteData.sublistView(
        File('assets/fonts/KoreanMemoSans-Regular.otf').readAsBytesSync(),
      ),
    );
  });
  test('bundled font covers every modern Hangul syllable including 까딱하면', () {
    expect([
      for (var cp = 0xac00; cp <= 0xd7a3; cp++)
        if (!glyphs.contains(cp)) cp,
    ], isEmpty);
    expect(
      '까딱하면 하마터면 자칫하면 ㄱㄲㄸㅏㅘ 각'.runes.where((cp) => !glyphs.contains(cp)),
      isEmpty,
    );
  });
  test('bundled Korean and Chinese vocabulary characters have real glyphs', () {
    final missing = <String>{};
    for (final path in [
      'assets/data/default_word_books.json',
      'assets/data/technical_word_books.json',
    ]) {
      final data = jsonDecode(File(path).readAsStringSync()) as Map;
      for (final book in data['books'] as List) {
        for (final word in book['words'] as List) {
          for (final field in ['korean', 'meaningZh']) {
            for (final cp in (word[field] as String).runes) {
              if (((cp >= 0x3400 && cp <= 0x9fff) ||
                      (cp >= 0xac00 && cp <= 0xd7a3)) &&
                  !glyphs.contains(cp)) {
                missing.add(String.fromCharCode(cp));
              }
            }
          }
        }
      }
    }
    expect(missing, isEmpty);
  });
  test(
    'all six themes use the packaged font and Flutter can load it',
    () async {
      final loader = FontLoader(AppTheme.fontFamily)
        ..addFont(rootBundle.load('assets/fonts/KoreanMemoSans-Regular.otf'));
      await loader.load();
      for (final preset in AppTheme.presets) {
        final theme = AppTheme.forPreset(preset);
        expect(theme.textTheme.headlineMedium!.fontFamily, AppTheme.fontFamily);
        expect(theme.textTheme.bodyMedium!.fontFamily, AppTheme.fontFamily);
      }
    },
  );
}

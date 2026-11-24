import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../domain/atlas_models.dart';

Future<Uint8List?> fetchAtlasBytes(Uri url) async {
  try {
    final response = await http.get(url).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;
    final type = response.headers['content-type'] ?? '';
    if (type.contains('text/html')) return null;
    return response.bodyBytes;
  } catch (_) {
    return null;
  }
}

class AtlasRemote {
  const AtlasRemote({this.base = atlasPublicBase});
  final String base;

  Future<AtlasIndex> loadIndex() async {
    final bytes = await fetchAtlasBytes(Uri.parse('$base/index.json'));
    if (bytes == null) throw const FormatException('暂时无法读取图鉴索引');
    return parseAtlasIndex(jsonDecode(utf8.decode(bytes)));
  }

  Future<List<AtlasEntryDraft>> loadChunk(int index) async {
    final bytes = await fetchAtlasBytes(Uri.parse('$base/entries/$index.json'));
    if (bytes == null) throw FormatException('暂时无法读取图鉴第 $index 块');
    return parseAtlasChunk(jsonDecode(utf8.decode(bytes)));
  }
}

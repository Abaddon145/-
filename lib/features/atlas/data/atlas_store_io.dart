import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'atlas_media_cache.dart';

Future<AtlasByteStore> openAtlasStore() async {
  final root = await getApplicationSupportDirectory();
  final directory = Directory('${root.path}/atlas-media');
  if (!directory.existsSync()) directory.createSync(recursive: true);
  return FileAtlasByteStore(directory);
}

class FileAtlasByteStore implements AtlasByteStore {
  FileAtlasByteStore(this.root);
  final Directory root;

  File get _manifest => File('${root.path}/manifest.json');

  Map<String, Map<String, Object?>> _readManifest() {
    if (!_manifest.existsSync()) return {};
    final raw = jsonDecode(_manifest.readAsStringSync());
    if (raw is! Map) return {};
    return {
      for (final entry in raw.entries)
        if (entry.value is Map)
          entry.key.toString(): Map<String, Object?>.from(entry.value as Map),
    };
  }

  void _writeManifest(Map<String, Map<String, Object?>> manifest) {
    _manifest.writeAsStringSync(jsonEncode(manifest));
  }

  String _fileName(String key) => sha1.convert(utf8.encode(key)).toString();

  @override
  Future<void> delete(String key) async {
    final manifest = _readManifest();
    final name = manifest[key]?['file']?.toString() ?? _fileName(key);
    final file = File('${root.path}/$name');
    if (file.existsSync()) file.deleteSync();
    manifest.remove(key);
    _writeManifest(manifest);
  }

  @override
  Future<List<AtlasCacheRecord>> list() async {
    final manifest = _readManifest();
    return [
      for (final entry in manifest.entries)
        AtlasCacheRecord(
          key: entry.key,
          bytes: entry.value['bytes'] as int? ?? 0,
          touchedAt: DateTime.fromMillisecondsSinceEpoch(
            entry.value['touched'] as int? ?? 0,
          ),
        ),
    ];
  }

  @override
  Future<Uint8List?> read(String key) async {
    final manifest = _readManifest();
    final item = manifest[key];
    if (item == null) return null;
    final file = File('${root.path}/${item['file']}');
    if (!file.existsSync()) {
      manifest.remove(key);
      _writeManifest(manifest);
      return null;
    }
    item['touched'] = DateTime.now().millisecondsSinceEpoch;
    _writeManifest(manifest);
    return file.readAsBytesSync();
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    final manifest = _readManifest();
    final name = _fileName(key);
    File('${root.path}/$name').writeAsBytesSync(bytes, flush: true);
    manifest[key] = {
      'file': name,
      'bytes': bytes.length,
      'touched': DateTime.now().millisecondsSinceEpoch,
    };
    _writeManifest(manifest);
  }
}

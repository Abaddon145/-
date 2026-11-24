import 'dart:typed_data';

class AtlasCacheRecord {
  const AtlasCacheRecord({
    required this.key,
    required this.bytes,
    required this.touchedAt,
  });

  final String key;
  final int bytes;
  final DateTime touchedAt;
}

abstract class AtlasByteStore {
  Future<Uint8List?> read(String key);
  Future<void> write(String key, Uint8List bytes);
  Future<void> delete(String key);
  Future<List<AtlasCacheRecord>> list();
}

class MemoryByteStore implements AtlasByteStore {
  final _bytes = <String, Uint8List>{};
  final _touched = <String, DateTime>{};
  var _tick = 0;
  DateTime _stamp() => DateTime.fromMillisecondsSinceEpoch(++_tick);

  @override
  Future<void> delete(String key) async {
    _bytes.remove(key);
    _touched.remove(key);
  }

  @override
  Future<List<AtlasCacheRecord>> list() async => [
    for (final entry in _bytes.entries)
      AtlasCacheRecord(
        key: entry.key,
        bytes: entry.value.length,
        touchedAt:
            _touched[entry.key] ?? DateTime.fromMillisecondsSinceEpoch(0),
      ),
  ];

  @override
  Future<Uint8List?> read(String key) async {
    final bytes = _bytes[key];
    if (bytes == null) return null;
    _touched[key] = _stamp();
    return bytes;
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    _bytes[key] = Uint8List.fromList(bytes);
    _touched[key] = _stamp();
  }
}

typedef AtlasFetcher = Future<Uint8List?> Function(Uri url);

class AtlasMediaCache {
  AtlasMediaCache({
    AtlasByteStore? store,
    Future<AtlasByteStore>? opening,
    this.maxBytes = 80 * 1024 * 1024,
    AtlasFetcher? fetcher,
    DateTime Function()? clock,
  }) : _store = opening ?? Future<AtlasByteStore>.value(store!),
       _fetcher = fetcher,
       _clock = clock ?? DateTime.now;

  final Future<AtlasByteStore> _store;
  final int maxBytes;
  final AtlasFetcher? _fetcher;
  final DateTime Function() _clock;

  Future<int> sizeBytes() async {
    final rows = await (await _store).list();
    return rows.fold<int>(0, (sum, row) => sum + row.bytes);
  }

  Future<void> clear() async {
    final store = await _store;
    for (final row in await store.list()) {
      await store.delete(row.key);
    }
  }

  Future<void> _evictTo(AtlasByteStore store, int budget) async {
    final rows = await store.list();
    rows.sort((a, b) => a.touchedAt.compareTo(b.touchedAt));
    var used = rows.fold<int>(0, (sum, row) => sum + row.bytes);
    for (final row in rows) {
      if (used <= budget) return;
      await store.delete(row.key);
      used -= row.bytes;
    }
  }

  /// Returns bytes from cache or [fetcher]. Network and decode failures
  /// return null so text study and system speech keep working.
  Future<Uint8List?> get(Uri url) async {
    final key = url.toString();
    try {
      final store = await _store;
      final cached = await store.read(key);
      if (cached != null) return cached;
      final fetched = await _fetcher?.call(url);
      if (fetched == null || fetched.isEmpty) return null;
      if (fetched.length > maxBytes) return fetched;
      await _evictTo(store, maxBytes - fetched.length);
      await store.write(key, fetched);
      await _evictTo(store, maxBytes);
      return fetched;
    } catch (_) {
      return null;
    }
  }

  DateTime get now => _clock();
}

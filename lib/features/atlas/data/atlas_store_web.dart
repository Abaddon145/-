import 'atlas_media_cache.dart';

/// Web keeps fetched atlas bytes in memory, capped by the cache. The app
/// service worker must not precache these cross-origin files.
Future<AtlasByteStore> openAtlasStore() async => MemoryByteStore();

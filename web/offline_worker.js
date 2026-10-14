// Own the app cache explicitly instead of relying on Flutter's deprecated worker.
const CACHE = 'korean-memo-0.6.1';
const CORE = ['./', 'index.html', 'flutter_bootstrap.js', 'main.dart.js',
  'sqlite3.wasm', 'drift_worker.js', 'manifest.json',
  'assets/FontManifest.json', 'assets/AssetManifest.bin.json',
  'assets/assets/data/default_word_books.json',
  'assets/assets/data/technical_word_books.json'];
self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(CORE)));
});
self.addEventListener('message', event => {
  if (event.data === 'ACTIVATE_UPDATE') self.skipWaiting();
});
self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    for (const name of await caches.keys()) {
      if (name.startsWith('korean-memo-') && name !== CACHE) await caches.delete(name);
    }
    await self.clients.claim();
  })());
});
self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;
  // Keep session-only proxy credentials out of CacheStorage, including same-origin proxies.
  if (event.request.headers.has('Authorization')) return;
  const url = new URL(event.request.url);
  // Cache only this app's static assets. Never intercept another service or user uploads.
  if (url.origin !== self.location.origin || !url.pathname.startsWith(new URL('./', self.location).pathname)) return;
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    const name = url.pathname.split('/').pop();
    const critical = event.request.mode === 'navigate' ||
      ['main.dart.js', 'flutter_bootstrap.js', 'index.html', 'version.json'].includes(name);
    if (!critical) {
      const cached = await cache.match(event.request);
      if (cached) return cached;
    }
    try {
      const response = await fetch(event.request, critical ? {cache: 'no-store'} : {});
      if (response.ok) await cache.put(event.request, response.clone());
      return response;
    } catch (error) {
      const cached = await cache.match(event.request);
      if (cached) return cached;
      if (event.request.mode === 'navigate') {
        const index = await cache.match('index.html');
        if (index) return index;
      }
      throw error;
    }
  })());
});

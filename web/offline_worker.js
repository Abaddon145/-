// Own the app cache explicitly instead of relying on Flutter's deprecated worker.
const CACHE = 'korean-memo-0.4.0';
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
  const url = new URL(event.request.url);
  // Cache only this app's static assets. Never intercept another service or user uploads.
  if (url.origin !== self.location.origin || !url.pathname.startsWith(new URL('./', self.location).pathname)) return;
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    try {
      const response = await fetch(event.request);
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

/* Crème De La Style — Service Worker v1 */
var CACHE = 'creme-v3';
var PRECACHE = [
  '/creme-app/',
  '/creme-app/index.html',
  '/creme-app/manifest.json',
  '/creme-app/icon-192.png',
  '/creme-app/icon-512.png'
];

self.addEventListener('install', function(e) {
  e.waitUntil(
    caches.open(CACHE).then(function(c) {
      return c.addAll(PRECACHE).catch(function() {});
    })
  );
  self.skipWaiting();
});

self.addEventListener('activate', function(e) {
  e.waitUntil(
    caches.keys().then(function(keys) {
      return Promise.all(
        keys.filter(function(k){ return k !== CACHE; })
            .map(function(k){ return caches.delete(k); })
      );
    })
  );
  self.clients.claim();
});

self.addEventListener('fetch', function(e) {
  var url = e.request.url;

  // Skip non-http/https requests (chrome-extension://, data:, etc.)
  if (!url.startsWith('http://') && !url.startsWith('https://')) return;

  // Network-first for Supabase API calls — never cache these
  if (url.includes('supabase.co')) {
    e.respondWith(
      fetch(e.request).catch(function() {
        return caches.match(e.request);
      })
    );
    return;
  }

  // Cache-first for app shell assets
  e.respondWith(
    caches.match(e.request).then(function(cached) {
      if (cached) return cached;
      return fetch(e.request).then(function(res) {
        // Only cache valid same-origin responses
        if (res && res.status === 200 && res.type === 'basic') {
          var clone = res.clone();
          caches.open(CACHE).then(function(c){ c.put(e.request, clone); });
        }
        return res;
      });
    })
  );
});

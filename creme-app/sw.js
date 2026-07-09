/* Crème De La Style — Service Worker */
var CACHE = 'creme-v6';
var PRECACHE = [
  './index.html',
  './manifest.json',
  './logo-mark.png',
  './icons/icon-192.png',
  './icons/icon-512.png'
];

self.addEventListener('install', function(e) {
  e.waitUntil(
    caches.open(CACHE).then(function(c) {
      return c.addAll(PRECACHE).catch(function(){});
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
  if (!url.startsWith('http://') && !url.startsWith('https://')) return;
  if (url.includes('supabase.co') || url.includes('googleapis')) return;
  e.respondWith(
    caches.match(e.request).then(function(cached) {
      return cached || fetch(e.request).catch(function() { return caches.match('./index.html'); });
    })
  );
});

/* ── Web Push: puts alerts in the phone's notification bar ── */
self.addEventListener('push', function(e) {
  var data = {};
  try { data = e.data ? e.data.json() : {}; } catch (err) {}
  var title = data.title || 'Crème De La Style';
  var options = {
    body: data.body || '',
    icon: './icons/icon-192.png',
    badge: './icons/icon-192.png',
    image: data.image_url || undefined,
    data: { link_tab: data.link_tab || null }
  };
  e.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', function(e) {
  e.notification.close();
  var tab = e.notification.data && e.notification.data.link_tab;
  e.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function(list) {
      for (var i = 0; i < list.length; i++) {
        var c = list[i];
        if ('focus' in c) {
          c.focus();
          if (tab) c.postMessage({ type: 'push-nav', tab: tab });
          return;
        }
      }
      if (clients.openWindow) return clients.openWindow('./');
    })
  );
});

// Stokvel Manager — service worker
//
// Kept deliberately minimal: this is a financial app, so we never want someone
// to open it offline and see stale balances without realizing it. This only
// caches the app shell (so the icon/splash work and the page can open at all
// without a connection) — it never touches Supabase requests, which always go
// straight to the network.

const CACHE_NAME = 'mk-shell-v1';
const SHELL_FILES = ['./index.html', './manifest.json', './icon-192.png', './icon-512.png'];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(SHELL_FILES)).catch(() => {})
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((names) =>
      Promise.all(names.filter((n) => n !== CACHE_NAME).map((n) => caches.delete(n)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  const url = new URL(req.url);

  // Only ever handle GETs to our own origin's app shell files. Everything else
  // (Supabase REST calls, the Supabase JS library, auth requests, anything
  // cross-origin) is left completely alone and goes straight to the network.
  if (req.method !== 'GET' || url.origin !== self.location.origin) return;
  if (!SHELL_FILES.some((f) => url.pathname.endsWith(f.replace('./', '/')) || url.pathname === '/' )) return;

  event.respondWith(
    fetch(req)
      .then((res) => {
        const copy = res.clone();
        caches.open(CACHE_NAME).then((cache) => cache.put(req, copy)).catch(() => {});
        return res;
      })
      .catch(() => caches.match(req).then((cached) => cached || caches.match('./index.html')))
  );
});

const C = 'planner-v5';
const FILES = ['./', 'index.html', 'manifest.webmanifest', 'icon-180-v3.png', 'icon-192-v3.png', 'icon-512-v3.png'];
self.addEventListener('install', e => { e.waitUntil(caches.open(C).then(c => c.addAll(FILES))); self.skipWaiting(); });
self.addEventListener('activate', e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k.startsWith('planner-') && k !== C).map(k => caches.delete(k)))).then(() => self.clients.claim())); });
// 先用网络（保证拿到新版），离线时用缓存
self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  const url = new URL(e.request.url);
  const base = new URL('./', self.location.href);
  if (url.origin !== base.origin || !FILES.some(file => new URL(file, base).pathname === url.pathname)) return;
  if (url.pathname.endsWith('version.json')) return;
  e.respondWith(fetch(e.request, {cache: 'no-cache'}).then(r => {
    if (r.ok) { const cp = r.clone(); e.waitUntil(caches.open(C).then(c => c.put(e.request, cp))); } return r;
  }).catch(() => caches.open(C).then(c => c.match(e.request, {ignoreSearch: true}))));
});

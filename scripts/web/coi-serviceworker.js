/* coi-serviceworker — enables SharedArrayBuffer on hosts that cannot send
 * COOP/COEP headers (GitHub Pages, itch). Served next to index.html and
 * loaded via a <script> tag; registers itself as a service worker that
 * re-serves every response with the two isolation headers, then reloads
 * the page once so the isolated context takes effect.
 * Deployed ONLY with the /threads/ A/B build (chat msg 156): browsers
 * without SharedArrayBuffer keep using the nothreads build at the root. */
if (typeof window === 'undefined') {
    /* ---- service worker scope ---- */
    self.addEventListener('install', function () { self.skipWaiting(); });
    self.addEventListener('activate', function (e) { e.waitUntil(self.clients.claim()); });
    self.addEventListener('fetch', function (e) {
        var r = e.request;
        if (r.cache === 'only-if-cached' && r.mode !== 'same-origin') return;
        e.respondWith(fetch(r).then(function (res) {
            if (res.status === 0) return res;
            var h = new Headers(res.headers);
            h.set('Cross-Origin-Embedder-Policy', 'credentialless');
            h.set('Cross-Origin-Opener-Policy', 'same-origin');
            h.set('Cross-Origin-Resource-Policy', 'cross-origin');
            return new Response(res.body, { status: res.status, statusText: res.statusText, headers: h });
        }).catch(function (err) { console.error(err); }));
    });
} else {
    /* ---- page scope ---- */
    (function () {
        var script = document.currentScript;
        if (window.crossOriginIsolated) return;        // headers already effective
        if (!('serviceWorker' in navigator)) return;   // nothing we can do
        if (window.sessionStorage && sessionStorage.getItem('coiReloaded')) return; // no loops
        navigator.serviceWorker.register(script.src).then(function (reg) {
            var reload = function () {
                if (window.sessionStorage) sessionStorage.setItem('coiReloaded', '1');
                window.location.reload();
            };
            if (reg.active && !navigator.serviceWorker.controller) { reload(); return; }
            reg.addEventListener('updatefound', function () {
                var w = reg.installing;
                if (!w) return;
                w.addEventListener('statechange', function () {
                    if (w.state === 'activated' && !navigator.serviceWorker.controller) reload();
                });
            });
        }).catch(function (err) { console.error('coi-serviceworker register failed', err); });
    })();
}

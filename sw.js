/* My Day Buddy service worker.
 *
 * Strategy, deliberately split:
 *   - The app shell (navigations + index.html) is NETWORK FIRST, so a new
 *     deploy shows up on the very next launch instead of one-or-more launches
 *     later. If the network is slow or gone, we fall back to the cached copy,
 *     so the app still opens on a plane.
 *   - Everything else (icon, manifest, fonts, the icon library) is served from
 *     cache immediately and refreshed in the background. Those rarely change
 *     and speed matters more than freshness.
 */
const CACHE_NAME = "daybuddy-cache-v9";
const SHELL = ["./", "./index.html", "./manifest.json", "./icon.svg",
               "./apple-touch-icon.png", "./icon-192.png", "./icon-512.png", "./icon-maskable-512.png"];
const NETWORK_TIMEOUT_MS = 3500;

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(SHELL)).catch(() => {})
  );
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

/* Is this a request for the app shell itself? */
function isShellRequest(request) {
  if (request.mode === "navigate") return true;
  const url = new URL(request.url);
  return url.origin === self.location.origin && /(^|\/)(index\.html)?$/.test(url.pathname);
}

/* Network first, with a timeout and a cache fallback. */
async function shellStrategy(request) {
  const cache = await caches.open(CACHE_NAME);
  let timer;
  try {
    const network = fetch(request, { cache: "reload" });
    const timeout = new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error("network timeout")), NETWORK_TIMEOUT_MS);
    });
    const response = await Promise.race([network, timeout]);
    if (response && response.status === 200) {
      cache.put(request, response.clone()).catch(() => {});
    }
    return response;
  } catch (e) {
    const cached = (await cache.match(request)) || (await cache.match("./index.html")) || (await cache.match("./"));
    if (cached) return cached;
    throw e;
  } finally {
    clearTimeout(timer);
  }
}

/* Cache first, refreshed in the background. */
async function assetStrategy(request) {
  const cache = await caches.open(CACHE_NAME);
  const cached = await cache.match(request);
  const network = fetch(request)
    .then((response) => {
      if (response && (response.status === 200 || response.type === "opaque")) {
        cache.put(request, response.clone()).catch(() => {});
      }
      return response;
    })
    .catch(() => cached);
  return cached || network;
}

self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") return;
  const url = new URL(event.request.url);
  if (url.protocol !== "http:" && url.protocol !== "https:") return;
  event.respondWith(
    isShellRequest(event.request) ? shellStrategy(event.request) : assetStrategy(event.request)
  );
});

/* Lets the page ask a waiting worker to take over straight away. */
self.addEventListener("message", (event) => {
  if (event.data === "skipWaiting") self.skipWaiting();
});

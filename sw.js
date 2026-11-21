/* Latin Food 20 · avisos de pedidos (Zerufy Studio)
   Solo muestra notificaciones push. No guarda nada en caché. */
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", e => e.waitUntil(self.clients.claim()));

self.addEventListener("push", e => {
  let d = {};
  try{ d = e.data ? e.data.json() : {}; }catch(_){ d = { body: e.data ? e.data.text() : "" }; }
  e.waitUntil(self.registration.showNotification(d.title || "Latin Food 20", {
    body: d.body || "",
    tag: d.tag || "lf20",
    renotify: true,
    icon: "/icon-192.png",
    badge: "/icon-192.png",
    vibrate: [220, 120, 220, 120, 400],
    data: { url: d.url || "/" },
  }));
});

self.addEventListener("notificationclick", e => {
  e.notification.close();
  const url = new URL((e.notification.data && e.notification.data.url) || "/", self.location.origin).href;
  e.waitUntil(self.clients.matchAll({ type: "window", includeUncontrolled: true }).then(ws => {
    for(const w of ws){ if(w.url === url && "focus" in w) return w.focus(); }
    return self.clients.openWindow(url);
  }));
});

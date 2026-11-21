// Avisos push de PEDIDOS (Zerufy Studio). Misma base que aviso-cita (claves VAPID en Vault).
// 1) La base la llama (trigger pedidos_aviso) con { id, tipo }:
//    · tipo "nuevo"  → aviso al teléfono de la dueña (push_subs de la tienda): "Pedido nuevo #7"
//    · tipo "estado" → aviso al teléfono del cliente (pedido_avisos): pago recibido / listo / cancelado
//    La función relee el pedido en la base y solo avisa si el cambio es reciente.
// 2) La pantalla de pedidos la llama con { prueba: true, store } y la sesión de la dueña.
import webpush from "npm:web-push@3.6.7";
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const URL_SB = Deno.env.get("SUPABASE_URL")!;
function serviceKey(): string {
  const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (legacy) return legacy;
  try { const k = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}"); return k.default ?? Object.values(k)[0] ?? ""; } catch { return ""; }
}
const sb = createClient(URL_SB, serviceKey(), { auth: { persistSession: false } });

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { ...CORS, "Content-Type": "application/json" } });
const dinero = (n: number) => "$" + Number(n).toFixed(2);

let vapidListo = false;
async function vapid() {
  if (vapidListo) return true;
  const { data, error } = await sb.rpc("aviso_vapid");
  if (error || !data?.public || !data?.private) return false;
  webpush.setVapidDetails("mailto:zerufystudio@gmail.com", data.public, data.private);
  return (vapidListo = true);
}

async function enviar(tabla: "push_subs" | "pedido_avisos", subs: any[], payload: string) {
  let ok = 0;
  for (const s of subs) {
    try {
      await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payload, { TTL: 3600, urgency: "high" });
      ok++;
    } catch (e) {
      const code = (e as { statusCode?: number }).statusCode;
      if (code === 404 || code === 410) await sb.from(tabla).delete().eq("id", s.id);
    }
  }
  return ok;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "método" }, 405);
  let body: any = {};
  try { body = await req.json(); } catch { return json({ error: "cuerpo" }, 400); }
  const claves = await vapid();
  if (!claves) return json({ error: "claves" }, 500);

  // ---- prueba desde pedidos.html ----
  if (body.prueba) {
    const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const { data: u } = await sb.auth.getUser(jwt);
    if (!u?.user) return json({ error: "sesión" }, 401);
    const store = Number(body.store);
    const { data: adm } = await sb.from("tienda_admins").select("store_id").eq("store_id", store).eq("user_id", u.user.id).maybeSingle();
    if (!adm) return json({ error: "permiso" }, 403);
    let q = sb.from("push_subs").select("*").eq("store_id", store);
    if (body.endpoint) q = q.eq("endpoint", String(body.endpoint));
    const { data: subs } = await q;
    const enviados = await enviar("push_subs", subs ?? [], JSON.stringify({
      title: "Avisos activados",
      body: "Así te van a llegar los pedidos nuevos.",
      tag: "prueba", url: "/pedidos.html",
    }));
    return json({ enviados, telefonos: subs?.length ?? 0 });
  }

  // ---- cambios de pedidos (los manda la base) ----
  const id = Number(body.id);
  if (!id) return json({ error: "id" }, 400);
  const { data: p } = await sb.from("pedidos").select("*").eq("id", id).maybeSingle();
  if (!p) return json({ enviados: 0, motivo: "no existe" });
  if (Date.now() - Date.parse(p.actualizado_en) > 10 * 60 * 1000) return json({ enviados: 0, motivo: "viejo" });
  const { data: t } = await sb.from("tiendas").select("nombre").eq("id", p.store_id).maybeSingle();
  const negocio = t?.nombre ?? "Tu pedido";
  const lugar = p.mesa ? `Mesa ${p.mesa}` : "Para recoger";

  if (body.tipo === "nuevo") {
    const { data: subs } = await sb.from("push_subs").select("*").eq("store_id", p.store_id);
    const piezas = (p.items ?? []).reduce((a: number, i: any) => a + (i.cant ?? 0), 0);
    const enviados = await enviar("push_subs", subs ?? [], JSON.stringify({
      title: `Pedido nuevo #${p.numero} · ${lugar}`,
      body: `${p.nombre} · ${piezas} ${piezas === 1 ? "artículo" : "artículos"} · ${dinero(p.total)}${p.cobro === "antes" ? " · por cobrar" : ""}`,
      tag: `pedido-${p.id}`, url: "/pedidos.html",
    }));
    return json({ enviados, telefonos: subs?.length ?? 0 });
  }

  // aviso al cliente según cómo quedó el pedido
  let title = "", texto = "";
  if (p.estado === "listo") { title = `¡Tu pedido #${p.numero} está listo!`; texto = p.pago === "pagado" ? "Pasa por la ventanilla y di tu número." : "Pasa por la ventanilla, pagas al recoger."; }
  else if (p.estado === "cancelado") { title = `Pedido #${p.numero} cancelado`; texto = `Si tienes dudas, pregunta en ${negocio}.`; }
  else if (p.pago === "pagado") { title = `Pago recibido · #${p.numero}`; texto = "Estamos preparando tu pedido. Te avisamos cuando esté listo."; }
  else return json({ enviados: 0, motivo: "sin aviso" });

  const { data: subs } = await sb.from("pedido_avisos").select("*").eq("pedido_id", p.id);
  const enviados = await enviar("pedido_avisos", subs ?? [], JSON.stringify({
    title, body: texto, tag: `pedido-${p.id}`, url: `/pedido.html?t=${p.token}`,
  }));
  return json({ enviados, telefonos: subs?.length ?? 0 });
});

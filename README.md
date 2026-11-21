# Latin Food 20 — menú digital con pedidos en vivo

Menú digital del food truck **Latin Food 20** (comida venezolana y latina). **Cliente** (familia de Leo). Es el mismo sistema de S91 House Grill, con la identidad de Latin Food 20.

| Archivo | Qué es |
|---|---|
| `index.html` | El menú que ve el cliente (QR o link). Intro que arma el logo pieza por pieza, hero con patrón, pestañas, favoritos, cada plato con su foto o el ícono de su categoría, carrito y pedido en línea, "Mi pedido", visor de fotos y copia local para cuando no hay señal |
| `admin.html` | Panel para cambiar platos, precios, fotos, agotados, favoritos, orden del menú y ajustes (aviso del día, dirección, WhatsApp, Instagram y horario) |
| `pedidos.html` | **Caja y cocina** (tablet o celular): pedidos por cobrar → pagados → en preparación → listos, historial del día, agotados con un toque, y QR y ajustes (prender pedidos, cobrar antes de preparar, mesas, avisos push). Se instala como la app "Caja LF20" |
| `pedido.html` | Lo que ve el cliente después de pedir: número, estados, aviso push y "Guardar mi pedido" |
| `qr.html` | QR imprimibles: "Para recoger" y uno por mesa (`?mesa=N`) |
| `privacidad.html` | Privacidad y condiciones de los pedidos |
| `img/` | Patrón de la marca (negro sobre rojo, rojo sobre negro, rojo sobre crema) |
| `sw.js`, `pedidos.webmanifest`, `icon-*.png`, `favicon.png` | Avisos push, app de caja e íconos |
| `supabase/` | Copia de referencia del SQL de pedidos v2 y de la función `aviso-pedido` (ya están aplicados y son los mismos de S91) |

**Supabase:** proyecto `zerufy-studio`, sistema de Menús, **`store_id = 9`** (tablas `tiendas`, `categorias`, `platos`, `ajustes`, `tienda_admins`, `pedidos`). Fotos en el bucket `menu`. Solo se usa la llave pública. La función `aviso-pedido` toma el nombre del negocio de `tiendas`, así que sirve igual que en S91.

**Pedidos en línea:** apagados hasta que se prendan en `pedidos.html` (`ajustes.pedidos_activos`). Para probar sin que los clientes lo vean, abre el menú con `?prueba=1` (los pedidos salen marcados como PRUEBA).

**Identidad:** rojo `#D12F22`, negro `#141414`, crema `#F6EBD9`, amarillo `#F5B700` (solo precios y promos). Tipografía Archivo (Google Fonts). Manual completo en el proyecto "LATIN FOOD 20".

**Hosting:** Cloudflare Pages en la cuenta de Zerufy Studio. Cada cambio en `main` se publica solo. Dominio: por definir (Namecheap → nameservers de Cloudflare, como S91).

Si la base de datos no responde, el menú sigue funcionando con los platos que vienen dentro de `index.html`.

---
Hecho por **Zerufy Studio** · zerufystudio.com · El mapa de todos los repos está en el README de `zerufy-studio`.

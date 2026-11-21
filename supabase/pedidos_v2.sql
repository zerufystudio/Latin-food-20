-- =====================================================================
-- PEDIDOS v2 (Zerufy Studio): mesa (QR por mesa), cobro en caja
-- (efectivo / transferencia) y avisos push. Sin opciones por plato:
-- cada producto entra con su precio fijo y solo cambia la cantidad.
-- Compatible con el menú anterior: crear_pedido acepta las mismas llamadas.
-- Proyecto: zerufy-studio · se aplica una sola vez.
-- =====================================================================

-- ajustes de la tienda
alter table public.ajustes add column if not exists cobro text not null default 'al_recoger'
  check (cobro in ('antes','al_recoger'));
alter table public.ajustes add column if not exists mesas integer not null default 0
  check (mesas between 0 and 99);
comment on column public.ajustes.cobro is 'PEDIDOS: antes = se paga en caja y después se prepara; al_recoger = se prepara y se cobra al entregar.';
comment on column public.ajustes.mesas is 'PEDIDOS: cuántas mesas tienen QR (0 = sin mesas fijas).';

-- pedidos: mesa, pago y modo de cobro
alter table public.pedidos add column if not exists mesa smallint check (mesa between 1 and 99);
alter table public.pedidos add column if not exists pago text not null default 'pendiente' check (pago in ('pendiente','pagado'));
alter table public.pedidos add column if not exists metodo_pago text check (metodo_pago in ('efectivo','transferencia','tarjeta'));
alter table public.pedidos add column if not exists pagado_en timestamptz;
alter table public.pedidos add column if not exists cobro text not null default 'al_recoger' check (cobro in ('antes','al_recoger'));
grant update (estado, pago, metodo_pago) on public.pedidos to authenticated;

create or replace function public.pedidos_pago() returns trigger
language plpgsql set search_path to 'public' as $$
begin
  if new.pago = 'pagado' and old.pago is distinct from 'pagado' then new.pagado_en := now(); end if;
  if new.pago = 'pendiente' then new.pagado_en := null; new.metodo_pago := null; end if;
  return new;
end $$;
drop trigger if exists pedidos_pago on public.pedidos;
create trigger pedidos_pago before update on public.pedidos
  for each row execute function public.pedidos_pago();

-- avisos push del cliente (solo se escriben con avisar_mi_pedido)
create table if not exists public.pedido_avisos (
  id bigint generated always as identity primary key,
  pedido_id bigint not null references public.pedidos(id) on delete cascade,
  endpoint text not null unique check (endpoint ~ '^https://' and char_length(endpoint) < 1000),
  p256dh text not null check (char_length(p256dh) between 20 and 200),
  auth text not null check (char_length(auth) between 8 and 100),
  creado_en timestamptz not null default now()
);
comment on table public.pedido_avisos is 'PEDIDOS: teléfonos de clientes que activaron el aviso de su pedido. Sin políticas a propósito: solo avisar_mi_pedido y la función aviso-pedido.';
alter table public.pedido_avisos enable row level security;
revoke all on public.pedido_avisos from anon, authenticated;

create or replace function public.avisar_mi_pedido(p_token uuid, p_endpoint text, p_p256dh text, p_auth text)
returns boolean language plpgsql security definer set search_path to 'public' as $$
declare v_id bigint;
begin
  select id into v_id from pedidos where token = p_token and creado_en > now() - interval '1 day';
  if v_id is null then return false; end if;
  insert into pedido_avisos (pedido_id, endpoint, p256dh, auth)
  values (v_id, p_endpoint, p_p256dh, p_auth)
  on conflict (endpoint) do update set pedido_id = excluded.pedido_id, p256dh = excluded.p256dh,
    auth = excluded.auth, creado_en = now();
  return true;
end $$;

-- crear pedido v2: mesa; el precio sale de platos (nunca del teléfono)
drop function if exists public.crear_pedido(bigint, text, text, jsonb, text, boolean);
create or replace function public.crear_pedido(
  p_store bigint, p_nombre text, p_telefono text, p_items jsonb,
  p_nota text default null, p_prueba boolean default false, p_mesa integer default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare
  v_tel text := regexp_replace(coalesce(p_telefono, ''), '\D', '', 'g');
  v_aj record;
  v_lineas jsonb := '[]'::jsonb;
  v_total numeric(10,2) := 0;
  v_linea jsonb; v_id bigint; v_cant integer; v_p record;
  v_piezas integer := 0; v_ids bigint[] := '{}';
  v_hoy date := (now() at time zone 'America/New_York')::date;
  v_num integer; v_token uuid;
begin
  select a.pedidos_activos, a.cobro, a.mesas into v_aj from ajustes a where a.store_id = p_store;
  if not found then raise exception 'tienda_invalida'; end if;
  if not v_aj.pedidos_activos and not coalesce(p_prueba, false) then raise exception 'pedidos_cerrados'; end if;
  if coalesce(trim(p_nombre), '') = '' then raise exception 'falta_nombre'; end if;
  if char_length(v_tel) = 10 then v_tel := '1' || v_tel; end if;
  if char_length(v_tel) < 11 or char_length(v_tel) > 15 then raise exception 'telefono_invalido'; end if;
  if p_mesa is not null and (p_mesa < 1 or p_mesa > 99 or (v_aj.mesas > 0 and p_mesa > v_aj.mesas)) then
    raise exception 'mesa_invalida';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'pedido_vacio'; end if;
  if jsonb_array_length(p_items) > 40 then raise exception 'pedido_muy_grande'; end if;

  for v_linea in select value from jsonb_array_elements(p_items) loop
    begin
      v_id := (v_linea ->> 'id')::bigint;
      v_cant := (v_linea ->> 'cant')::integer;
    exception when others then raise exception 'linea_invalida';
    end;
    if v_id is null or v_cant is null or v_cant < 1 or v_cant > 20 then raise exception 'linea_invalida'; end if;
    v_piezas := v_piezas + v_cant;
    if v_id = any(v_ids) then raise exception 'linea_repetida'; end if;
    v_ids := v_ids || v_id;

    select p.id, p.nombre, p.precio into v_p
      from platos p join categorias c on c.id = p.categoria_id
      where p.id = v_id and p.store_id = p_store and p.disponible and c.visible and p.precio is not null;
    if not found then raise exception 'plato_no_disponible:%', v_id; end if;

    v_lineas := v_lineas || jsonb_build_object('id', v_p.id, 'nombre', v_p.nombre, 'precio', v_p.precio, 'cant', v_cant);
    v_total := v_total + v_p.precio * v_cant;
  end loop;
  if v_piezas > 60 then raise exception 'pedido_muy_grande'; end if;

  if (select count(*) from pedidos
        where store_id = p_store and telefono = v_tel and estado in ('recibido','preparando')
          and creado_en > now() - interval '6 hours') >= 3 then
    raise exception 'demasiados_pedidos';
  end if;

  perform pg_advisory_xact_lock(91000 + p_store::int, (v_hoy - date '2000-01-01'));
  select coalesce(max(numero), 0) + 1 into v_num from pedidos
    where store_id = p_store and creado_en >= (v_hoy::timestamp at time zone 'America/New_York');

  insert into pedidos (store_id, numero, nombre, telefono, items, total, nota, prueba, mesa, cobro)
  values (p_store, v_num, left(trim(p_nombre), 60), v_tel, v_lineas, v_total,
          nullif(left(trim(coalesce(p_nota, '')), 300), ''), coalesce(p_prueba, false), p_mesa, v_aj.cobro)
  returning token into v_token;

  return jsonb_build_object('token', v_token, 'numero', v_num, 'total', v_total, 'cobro', v_aj.cobro);
end $$;

create or replace function public.ver_pedido(p_token uuid)
returns jsonb language sql stable security definer set search_path to 'public' as $$
  select jsonb_build_object(
    'numero', p.numero, 'nombre', p.nombre, 'items', p.items, 'total', p.total, 'nota', p.nota,
    'estado', p.estado, 'pago', p.pago, 'metodo_pago', p.metodo_pago, 'pagado_en', p.pagado_en,
    'cobro', p.cobro, 'mesa', p.mesa, 'prueba', p.prueba,
    'creado_en', p.creado_en, 'actualizado_en', p.actualizado_en,
    'tienda', t.nombre, 'direccion', a.direccion, 'maps_url', a.maps_url)
  from pedidos p join tiendas t on t.id = p.store_id left join ajustes a on a.store_id = p.store_id
  where p.token = p_token and p.creado_en > now() - interval '2 days';
$$;

revoke all on function public.crear_pedido(bigint, text, text, jsonb, text, boolean, integer) from public;
grant execute on function public.crear_pedido(bigint, text, text, jsonb, text, boolean, integer) to anon, authenticated;
revoke all on function public.ver_pedido(uuid) from public;
grant execute on function public.ver_pedido(uuid) to anon, authenticated;
revoke all on function public.avisar_mi_pedido(uuid, text, text, text) from public;
grant execute on function public.avisar_mi_pedido(uuid, text, text, text) to anon, authenticated;

-- avisos: pedido nuevo → dueña; pagado / listo / cancelado → cliente
create or replace function public.avisar_pedido() returns trigger
language plpgsql security definer set search_path to 'public' as $$
declare v_tipo text;
begin
  if tg_op = 'INSERT' then v_tipo := 'nuevo';
  elsif new.estado is distinct from old.estado and new.estado in ('listo','cancelado') then v_tipo := 'estado';
  elsif new.pago = 'pagado' and old.pago is distinct from 'pagado' then v_tipo := 'estado';
  end if;
  if v_tipo is not null then
    perform net.http_post(
      url := 'https://tamsbliwhkrmkcljkltd.supabase.co/functions/v1/aviso-pedido',
      body := jsonb_build_object('id', new.id, 'tipo', v_tipo),
      headers := jsonb_build_object('Content-Type', 'application/json'));
  end if;
  return new;
end $$;
revoke all on function public.avisar_pedido() from public, anon, authenticated;
drop trigger if exists pedidos_aviso on public.pedidos;
create trigger pedidos_aviso after insert or update on public.pedidos
  for each row execute function public.avisar_pedido();

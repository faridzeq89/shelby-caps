-- ============================================================================
-- Fase 9 — Catálogo público para la tienda web.
-- Corre este script en el editor SQL del proyecto NUEVO del cliente.
--
-- Modelo de seguridad (importante):
--   * La tienda web es PÚBLICA, así que la llave `anon` queda expuesta en el
--     sitio. Por eso el catálogo es SOLO LECTURA para `anon`.
--   * El POS publica el catálogo llamando a `publish_catalog(secret, ...)`, que
--     valida un secreto guardado en `catalog_config` (que `anon` NO puede leer).
--     El secreto vive en el POS (app), nunca en la web.
-- ============================================================================

-- 1) Tablas del catálogo. Los `id` son los ids locales del POS (single-tenant:
--    un solo dispositivo es la fuente de la verdad y publica el snapshot).
create table if not exists public.catalog_products (
  id               bigint primary key,
  name             text not null,
  brand            text,
  category         text,
  base_price_cents integer not null,
  tax_rate_bps     integer not null default 1600,
  active           boolean not null default true,
  updated_at       timestamptz not null default now()
);

create table if not exists public.catalog_variants (
  id          bigint primary key,
  product_id  bigint not null,
  sku         text,
  size        text,
  color       text,
  price_cents integer not null,
  stock       integer not null default 0,
  active      boolean not null default true
);
create index if not exists idx_catalog_variants_product
  on public.catalog_variants (product_id);

create table if not exists public.catalog_price_tiers (
  id          bigserial primary key,
  product_id  bigint not null,
  min_qty     integer not null,
  price_cents integer not null
);
create index if not exists idx_catalog_tiers_product
  on public.catalog_price_tiers (product_id);

-- 2) Config privada: el secreto de publicación. `anon` NO lo lee (RLS sin
--    políticas de select para anon).
create table if not exists public.catalog_config (
  id             integer primary key default 1,
  publish_secret text not null,
  constraint catalog_config_singleton check (id = 1)
);

-- 3) RLS: la web (`anon`) SOLO LEE el catálogo; nadie escribe por PostgREST.
alter table public.catalog_products    enable row level security;
alter table public.catalog_variants    enable row level security;
alter table public.catalog_price_tiers enable row level security;
alter table public.catalog_config      enable row level security; -- sin políticas => anon no accede

drop policy if exists "anon read products" on public.catalog_products;
create policy "anon read products" on public.catalog_products
  for select to anon using (true);

drop policy if exists "anon read variants" on public.catalog_variants;
create policy "anon read variants" on public.catalog_variants
  for select to anon using (true);

drop policy if exists "anon read tiers" on public.catalog_price_tiers;
create policy "anon read tiers" on public.catalog_price_tiers
  for select to anon using (true);

-- 4) Publicación segura: reemplaza el snapshot completo. SECURITY DEFINER corre
--    como el dueño (ignora RLS); valida el secreto antes de tocar nada.
create or replace function public.publish_catalog(
  p_secret   text,
  p_products jsonb,
  p_variants jsonb,
  p_tiers    jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_secret text;
begin
  select publish_secret into v_secret from public.catalog_config where id = 1;
  if v_secret is null then
    raise exception 'catalog_config sin secreto: corre el paso 6 del script';
  end if;
  if p_secret is null or p_secret <> v_secret then
    raise exception 'secreto de publicacion invalido';
  end if;

  delete from public.catalog_price_tiers;
  delete from public.catalog_variants;
  delete from public.catalog_products;

  insert into public.catalog_products
    (id, name, brand, category, base_price_cents, tax_rate_bps, active, updated_at)
  select (e->>'id')::bigint, e->>'name', e->>'brand', e->>'category',
         (e->>'base_price_cents')::integer,
         coalesce((e->>'tax_rate_bps')::integer, 1600),
         coalesce((e->>'active')::boolean, true), now()
  from jsonb_array_elements(coalesce(p_products, '[]'::jsonb)) e;

  insert into public.catalog_variants
    (id, product_id, sku, size, color, price_cents, stock, active)
  select (e->>'id')::bigint, (e->>'product_id')::bigint, e->>'sku',
         e->>'size', e->>'color', (e->>'price_cents')::integer,
         coalesce((e->>'stock')::integer, 0),
         coalesce((e->>'active')::boolean, true)
  from jsonb_array_elements(coalesce(p_variants, '[]'::jsonb)) e;

  insert into public.catalog_price_tiers (product_id, min_qty, price_cents)
  select (e->>'product_id')::bigint, (e->>'min_qty')::integer,
         (e->>'price_cents')::integer
  from jsonb_array_elements(coalesce(p_tiers, '[]'::jsonb)) e;
end;
$$;

-- `anon` puede EJECUTAR la función, pero necesita el secreto (que no está en la web).
revoke all on function public.publish_catalog(text, jsonb, jsonb, jsonb) from public;
grant execute on function public.publish_catalog(text, jsonb, jsonb, jsonb) to anon;

-- 5) (Opcional) Endurecer: quitar el acceso de anon a otras funciones no aplica aquí.

-- 6) FIJA TU SECRETO DE PUBLICACIÓN — cámbialo por uno largo y tuyo, y ponlo
--    igual en el POS (Admin → Catálogo web → Secreto de publicación):
--
--    insert into public.catalog_config (id, publish_secret)
--    values (1, 'CAMBIA-ESTO-POR-UN-SECRETO-LARGO')
--    on conflict (id) do update set publish_secret = excluded.publish_secret;

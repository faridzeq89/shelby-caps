-- ============================================================================
-- Mayoreo por total de carrito (rediseño 2026-08-29).
-- Corre este script DESPUÉS de 0008_fix_categories_delete.sql, mismo proyecto.
--
-- Qué cambia: el mayoreo dejó de ser escalones por producto (tabla
-- `catalog_price_tiers`) y pasó a ser UN precio por producto
-- (`catalog_products.wholesale_price_cents`) que la tienda activa por el TOTAL
-- de piezas del carrito, contra un umbral global (`catalog_settings`).
--
-- `catalog_price_tiers` se CONSERVA (no se borra) para que un APK anterior que
-- todavía publique con `p_tiers` no truene; la tienda simplemente ya no la lee.
-- ============================================================================

-- 1) Precio de mayoreo por producto (nulo => sin mayoreo).
alter table public.catalog_products
  add column if not exists wholesale_price_cents integer;

-- 2) Config pública que la tienda SÍ puede leer (a diferencia de catalog_config,
--    que guarda el secreto). Aquí vive el umbral global de mayoreo.
create table if not exists public.catalog_settings (
  id                  integer primary key default 1,
  wholesale_threshold integer not null default 10,
  constraint catalog_settings_singleton check (id = 1)
);
insert into public.catalog_settings (id, wholesale_threshold)
  values (1, 10)
  on conflict (id) do nothing;

alter table public.catalog_settings enable row level security;
drop policy if exists "anon read settings" on public.catalog_settings;
create policy "anon read settings" on public.catalog_settings
  for select to anon using (true);

-- 3) publish_catalog v5: agrega el umbral de mayoreo. Ahora es la firma canónica
--    y lee `wholesale_price_cents` de cada producto en `p_products`. Las firmas
--    de 7 y 6 argumentos quedan como envoltorios (un APK viejo sigue publicando;
--    pasa NULL de umbral, que significa "no lo toques").
create or replace function public.publish_catalog(
  p_secret              text,
  p_products            jsonb,
  p_variants            jsonb,
  p_tiers               jsonb,
  p_images              jsonb,
  p_banners             jsonb,
  p_categories          jsonb,
  p_wholesale_threshold integer
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
    raise exception 'catalog_config sin secreto: corre el ultimo bloque de 0002';
  end if;
  if p_secret is null or p_secret <> v_secret then
    raise exception 'secreto de publicacion invalido';
  end if;

  truncate table public.catalog_banners,
                 public.catalog_images,
                 public.catalog_price_tiers,
                 public.catalog_variants,
                 public.catalog_products
    restart identity;

  insert into public.catalog_products
    (id, name, brand, category, description, base_price_cents,
     wholesale_price_cents, tax_rate_bps, active, updated_at)
  select (e->>'id')::bigint, e->>'name', e->>'brand', e->>'category',
         e->>'description',
         (e->>'base_price_cents')::integer,
         (e->>'wholesale_price_cents')::integer,
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

  -- Se conserva por compatibilidad con APKs viejos que aún mandan p_tiers.
  insert into public.catalog_price_tiers (product_id, min_qty, price_cents)
  select (e->>'product_id')::bigint, (e->>'min_qty')::integer,
         (e->>'price_cents')::integer
  from jsonb_array_elements(coalesce(p_tiers, '[]'::jsonb)) e;

  insert into public.catalog_images (product_id, url, position)
  select (e->>'product_id')::bigint, e->>'url',
         coalesce((e->>'position')::integer, 0)
  from jsonb_array_elements(coalesce(p_images, '[]'::jsonb)) e;

  insert into public.catalog_banners (url, caption, link, position, is_cover)
  select e->>'url', e->>'caption', e->>'link',
         coalesce((e->>'position')::integer, 0),
         coalesce((e->>'is_cover')::boolean, false)
  from jsonb_array_elements(coalesce(p_banners, '[]'::jsonb)) e;

  if p_categories is not null then
    -- TRUNCATE, no DELETE: Supabase aborta cualquier `delete` sin WHERE
    -- ("DELETE requires a WHERE clause", 21000). Es el mismo bug que arregló el
    -- 0008 y que no hay que reintroducir al copiar el cuerpo.
    truncate table public.catalog_categories;
    insert into public.catalog_categories (name, position, active)
    select e->>'name',
           coalesce((e->>'position')::integer, 0),
           coalesce((e->>'active')::boolean, true)
    from jsonb_array_elements(p_categories) e
    where coalesce(e->>'name', '') <> ''
    on conflict (name) do nothing;
  end if;

  -- NULL => "no traigo umbral" (APK viejo): no se toca el que ya está.
  if p_wholesale_threshold is not null then
    insert into public.catalog_settings (id, wholesale_threshold)
    values (1, greatest(p_wholesale_threshold, 1))
    on conflict (id) do update
      set wholesale_threshold = excluded.wholesale_threshold;
  end if;
end;
$$;

-- La firma de 7 argumentos (sin umbral) delega en la nueva con NULL.
create or replace function public.publish_catalog(
  p_secret text, p_products jsonb, p_variants jsonb, p_tiers jsonb,
  p_images jsonb, p_banners jsonb, p_categories jsonb
) returns void
language sql
security definer
set search_path = public
as $$
  select public.publish_catalog(p_secret, p_products, p_variants, p_tiers,
                                p_images, p_banners, p_categories, null::integer);
$$;

-- La firma de 6 argumentos (sin categorías) ya delegaba en la de 7 (0007); se
-- mantiene tal cual, así que la cadena queda 6 → 7 → 8.

revoke all on function public.publish_catalog(text, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, integer) from public;
grant execute on function public.publish_catalog(text, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, integer) to anon;
revoke all on function public.publish_catalog(text, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb) from public;
grant execute on function public.publish_catalog(text, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb) to anon;

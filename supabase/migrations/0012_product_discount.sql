-- ============================================================================
-- Descuento de oferta por producto en la tienda (fijo o %).
-- Corre DESPUÉS de 0009_wholesale.sql, en el proyecto de la tienda.
--
-- El descuento viaja DENTRO de cada producto en `p_products` (como
-- wholesale_price_cents), así que NO cambia la firma de publish_catalog: solo
-- se agregan columnas y el insert las lee. Un APK viejo que no manda estos
-- campos simplemente los deja en NULL (sin oferta).
-- ============================================================================

alter table public.catalog_products
  add column if not exists discount_kind  text,
  add column if not exists discount_value integer;

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
     wholesale_price_cents, discount_kind, discount_value,
     tax_rate_bps, active, updated_at)
  select (e->>'id')::bigint, e->>'name', e->>'brand', e->>'category',
         e->>'description',
         (e->>'base_price_cents')::integer,
         (e->>'wholesale_price_cents')::integer,
         e->>'discount_kind',
         (e->>'discount_value')::integer,
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
    truncate table public.catalog_categories;
    insert into public.catalog_categories (name, position, active)
    select e->>'name',
           coalesce((e->>'position')::integer, 0),
           coalesce((e->>'active')::boolean, true)
    from jsonb_array_elements(p_categories) e
    where coalesce(e->>'name', '') <> ''
    on conflict (name) do nothing;
  end if;

  if p_wholesale_threshold is not null then
    insert into public.catalog_settings (id, wholesale_threshold)
    values (1, greatest(p_wholesale_threshold, 1))
    on conflict (id) do update
      set wholesale_threshold = excluded.wholesale_threshold;
  end if;
end;
$$;

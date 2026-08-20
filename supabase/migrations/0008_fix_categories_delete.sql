-- ============================================================================
-- Arregla `publish_catalog` v4: el bloque de categorías usaba DELETE sin WHERE.
--
-- Supabase trae una protección que aborta cualquier `delete` sin `where`
-- ("DELETE requires a WHERE clause", SQLSTATE 21000). Por eso el resto de la
-- función usa TRUNCATE, y 0002 ya lo decía en un comentario. Con el DELETE, la
-- publicación entera moría en el último paso: el catálogo del cliente se quedó
-- congelado (20 ago 2026).
--
-- Corre este script DESPUÉS de 0007_catalog_categories.sql.
-- ============================================================================

create or replace function public.publish_catalog(
  p_secret     text,
  p_products   jsonb,
  p_variants   jsonb,
  p_tiers      jsonb,
  p_images     jsonb,
  p_banners    jsonb,
  p_categories jsonb
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
    (id, name, brand, category, description, base_price_cents, tax_rate_bps,
     active, updated_at)
  select (e->>'id')::bigint, e->>'name', e->>'brand', e->>'category',
         e->>'description',
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

  insert into public.catalog_images (product_id, url, position)
  select (e->>'product_id')::bigint, e->>'url',
         coalesce((e->>'position')::integer, 0)
  from jsonb_array_elements(coalesce(p_images, '[]'::jsonb)) e;

  insert into public.catalog_banners (url, caption, link, position, is_cover)
  select e->>'url', e->>'caption', e->>'link',
         coalesce((e->>'position')::integer, 0),
         coalesce((e->>'is_cover')::boolean, false)
  from jsonb_array_elements(coalesce(p_banners, '[]'::jsonb)) e;

  -- Aquí estaba el bug: `delete from public.catalog_categories;` sin WHERE.
  -- TRUNCATE va aparte del de arriba a propósito: este bloque solo corre cuando
  -- el POS manda categorías (NULL = "no las toques", para que un equipo con el
  -- APK viejo no le borre el orden al del mostrador).
  if p_categories is not null then
    truncate table public.catalog_categories;
    -- `on conflict` porque dos categorías locales pueden llamarse igual (el POS
    -- no lo impide) y el nombre es la llave: gana la primera, y publicar no debe
    -- fallar por eso.
    insert into public.catalog_categories (name, position, active)
    select e->>'name',
           coalesce((e->>'position')::integer, 0),
           coalesce((e->>'active')::boolean, true)
    from jsonb_array_elements(p_categories) e
    where coalesce(e->>'name', '') <> ''
    on conflict (name) do nothing;
  end if;
end;
$$;

revoke all on function public.publish_catalog(text, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb) from public;
grant execute on function public.publish_catalog(text, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb) to anon;

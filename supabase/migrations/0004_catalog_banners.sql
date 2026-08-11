-- ============================================================================
-- Anuncios de la tienda: portada y banners que rotan.
-- Corre este script DESPUÉS de 0003_catalog_images.sql, en el mismo proyecto.
--
-- No son productos: son solo imágenes que el dueño sube desde el POS para
-- anunciar promociones. Viajan por el mismo `publish_catalog` para que todo se
-- publique de una vez y no queden estados a medias.
-- ============================================================================

create table if not exists public.catalog_banners (
  id        bigserial primary key,
  url       text not null,
  caption   text,
  link      text,
  position  integer not null default 0,
  is_cover  boolean not null default false
);
create index if not exists idx_catalog_banners_pos
  on public.catalog_banners (is_cover, position);

alter table public.catalog_banners enable row level security;

drop policy if exists "anon read banners" on public.catalog_banners;
create policy "anon read banners" on public.catalog_banners
  for select to anon using (true);

-- publish_catalog v3: agrega los anuncios. Se conservan las firmas de 5 y 4
-- argumentos como envoltorios, para que un APK anterior siga publicando en vez
-- de tronar (solo que sin anuncios).
create or replace function public.publish_catalog(
  p_secret   text,
  p_products jsonb,
  p_variants jsonb,
  p_tiers    jsonb,
  p_images   jsonb,
  p_banners  jsonb
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
end;
$$;

-- La firma de 5 argumentos (sin anuncios) delega en la nueva.
create or replace function public.publish_catalog(
  p_secret text, p_products jsonb, p_variants jsonb, p_tiers jsonb,
  p_images jsonb
) returns void
language sql
security definer
set search_path = public
as $$
  select public.publish_catalog(p_secret, p_products, p_variants, p_tiers,
                                p_images, '[]'::jsonb);
$$;

revoke all on function public.publish_catalog(text, jsonb, jsonb, jsonb, jsonb, jsonb) from public;
grant execute on function public.publish_catalog(text, jsonb, jsonb, jsonb, jsonb, jsonb) to anon;
revoke all on function public.publish_catalog(text, jsonb, jsonb, jsonb, jsonb) from public;
grant execute on function public.publish_catalog(text, jsonb, jsonb, jsonb, jsonb) to anon;

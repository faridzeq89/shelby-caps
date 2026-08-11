-- ============================================================================
-- Fase 9b — Fotos del catálogo web (varias por producto).
-- Corre este script DESPUÉS de 0002_catalog.sql, en el mismo proyecto.
--
-- Por qué: una gorra se vende por cómo se ve, y una sola foto no basta (frente,
-- perfil, atrás, logo). El POS guarda las fotos como archivos locales, que la
-- web no puede leer; por eso al publicar se suben a Storage (bucket público
-- `catalog`) y aquí solo viajan las URLs.
--
-- La foto principal es `position = 0`. El resto es la galería, en orden.
-- ============================================================================

-- 1) Bucket PÚBLICO para las fotos del catálogo. Es público a propósito: son
--    las fotos de la tienda en línea. (El bucket `backups` sigue siendo privado.)
insert into storage.buckets (id, name, public)
values ('catalog', 'catalog', true)
on conflict (id) do update set public = true;

-- El POS sube con la llave anon, así que necesita insert/update SOLO en este
-- bucket. Cualquiera con la llave pública podría subir ahí: es el mismo
-- compromiso que ya aceptamos en 0001 para los respaldos (un solo negocio).
drop policy if exists "catalog anon read" on storage.objects;
create policy "catalog anon read"
  on storage.objects for select to anon
  using (bucket_id = 'catalog');

drop policy if exists "catalog anon insert" on storage.objects;
create policy "catalog anon insert"
  on storage.objects for insert to anon
  with check (bucket_id = 'catalog');

drop policy if exists "catalog anon update" on storage.objects;
create policy "catalog anon update"
  on storage.objects for update to anon
  using (bucket_id = 'catalog')
  with check (bucket_id = 'catalog');

-- 2) Descripción del producto: el catálogo la muestra bajo el nombre ("Gorra
--    negra de malla con visera curva") y 0002 no la contemplaba.
alter table public.catalog_products
  add column if not exists description text;

-- 3) Tabla de imágenes del snapshot publicado.
create table if not exists public.catalog_images (
  id         bigserial primary key,
  product_id bigint not null,
  url        text not null,
  position   integer not null default 0
);
create index if not exists idx_catalog_images_product
  on public.catalog_images (product_id, position);

alter table public.catalog_images enable row level security;

drop policy if exists "anon read images" on public.catalog_images;
create policy "anon read images" on public.catalog_images
  for select to anon using (true);

-- 4) publish_catalog v2: mismo contrato, más un cuarto arreglo con las fotos.
--    Se mantiene la firma vieja (4 argumentos) como envoltorio para que una
--    versión anterior del APK siga publicando sin fotos en vez de tronar.
create or replace function public.publish_catalog(
  p_secret   text,
  p_products jsonb,
  p_variants jsonb,
  p_tiers    jsonb,
  p_images   jsonb
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

  truncate table public.catalog_images,
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
end;
$$;

-- La firma vieja (sin fotos) delega en la nueva con una lista vacía.
create or replace function public.publish_catalog(
  p_secret   text,
  p_products jsonb,
  p_variants jsonb,
  p_tiers    jsonb
) returns void
language sql
security definer
set search_path = public
as $$
  select public.publish_catalog(p_secret, p_products, p_variants, p_tiers,
                                '[]'::jsonb);
$$;

revoke all on function public.publish_catalog(text, jsonb, jsonb, jsonb, jsonb) from public;
grant execute on function public.publish_catalog(text, jsonb, jsonb, jsonb, jsonb) to anon;
revoke all on function public.publish_catalog(text, jsonb, jsonb, jsonb) from public;
grant execute on function public.publish_catalog(text, jsonb, jsonb, jsonb) to anon;

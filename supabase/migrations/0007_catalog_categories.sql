-- ============================================================================
-- Categorías publicadas: el ORDEN lo decide el dueño, no el abecedario.
-- Corre este script DESPUÉS de 0006_business_card.sql, en el mismo proyecto.
--
-- Por qué existe: hasta hoy la tienda web no recibía las categorías. Las
-- deducía de los productos publicados y las acomodaba alfabéticamente, así que
-- "NEW ERA" salía después de "LIMPIEZA" aunque sea lo que más vende, y una
-- categoría archivada en el POS seguía apareciendo como botón mientras tuviera
-- un producto colgando.
--
-- Con esta tabla la tienda recibe la lista completa: el orden que el dueño
-- acomodó a mano (`position`) y si está archivada (`active`).
-- ============================================================================

-- El nombre es la llave: es lo único que la tienda conoce de una categoría (los
-- productos publicados traen `category` como texto, no el id local del POS).
create table if not exists public.catalog_categories (
  name     text primary key,
  position integer not null default 0,
  active   boolean not null default true
);
create index if not exists idx_catalog_categories_pos
  on public.catalog_categories (active, position);

alter table public.catalog_categories enable row level security;

drop policy if exists "anon read categories" on public.catalog_categories;
create policy "anon read categories" on public.catalog_categories
  for select to anon using (true);

-- publish_catalog v4: agrega las categorías. La firma de 6 argumentos se
-- conserva como envoltorio para que un APK anterior siga publicando en vez de
-- tronar; pasa NULL, y NULL significa "no traigo categorías, no me las toques"
-- (distinto de '[]', que sí las vacía). Así un equipo con la versión vieja no
-- le borra el orden al equipo del mostrador.
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

  if p_categories is not null then
    delete from public.catalog_categories;
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

-- La firma de 6 argumentos (sin categorías) delega en la nueva con NULL.
create or replace function public.publish_catalog(
  p_secret text, p_products jsonb, p_variants jsonb, p_tiers jsonb,
  p_images jsonb, p_banners jsonb
) returns void
language sql
security definer
set search_path = public
as $$
  select public.publish_catalog(p_secret, p_products, p_variants, p_tiers,
                                p_images, p_banners, null::jsonb);
$$;

revoke all on function public.publish_catalog(text, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb) from public;
grant execute on function public.publish_catalog(text, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb) to anon;
revoke all on function public.publish_catalog(text, jsonb, jsonb, jsonb, jsonb, jsonb) from public;
grant execute on function public.publish_catalog(text, jsonb, jsonb, jsonb, jsonb, jsonb) to anon;

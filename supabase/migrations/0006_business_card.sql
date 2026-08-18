-- ============================================================================
-- Tarjeta digital: página pública única con redes, envíos, forma de pago,
-- promociones y lealtad. Corre este script DESPUÉS de 0002_catalog.sql (usa
-- el mismo secreto de publicación, no crea uno nuevo).
--
-- Modelo de seguridad: igual que el catálogo — `anon` SOLO LEE; se publica
-- con `publish_business_card(secret, data)`, que valida contra el mismo
-- `catalog_config.publish_secret` que ya usa `publish_catalog`.
--
-- Contenido de presentación (no se reporta ni se cruza contra nada), así que
-- se guarda como UN registro con un solo campo `jsonb` en vez de columnas
-- normalizadas — la forma no cambia sin otra migración cada vez que el dueño
-- pida un campo más.
-- ============================================================================

create table if not exists public.business_card (
  id         integer primary key default 1,
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  constraint business_card_singleton check (id = 1)
);

alter table public.business_card enable row level security;

drop policy if exists "anon read business card" on public.business_card;
create policy "anon read business card" on public.business_card
  for select to anon using (true);

create or replace function public.publish_business_card(
  p_secret text,
  p_data   jsonb
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
    raise exception 'catalog_config sin secreto: corre 0002_catalog.sql primero';
  end if;
  if p_secret is null or p_secret <> v_secret then
    raise exception 'secreto de publicacion invalido';
  end if;

  insert into public.business_card (id, data, updated_at)
  values (1, coalesce(p_data, '{}'::jsonb), now())
  on conflict (id) do update
    set data = excluded.data, updated_at = excluded.updated_at;
end;
$$;

revoke all on function public.publish_business_card(text, jsonb) from public;
grant execute on function public.publish_business_card(text, jsonb) to anon;

-- ============================================================================
-- Cupones de descuento de la tienda en línea (porcentaje o monto fijo).
-- Corre DESPUÉS de 0005_orders.sql, en el proyecto de la tienda.
--
-- Los códigos NO se listan públicamente: `anon` solo puede VALIDAR un código
-- que ya conoce (validate_coupon). La gestión (crear/listar/borrar) valida el
-- secreto de publicación (catalog_config), igual que list_orders/publish_*.
-- El cobro (`process-payment`, service role) aplica el descuento de forma
-- autoritativa; el navegador nunca decide el monto.
-- ============================================================================

create table if not exists public.coupons (
  code       text primary key,
  kind       text not null check (kind in ('percent', 'fixed')),
  -- percent: 1..100 (porcentaje). fixed: centavos a descontar.
  value      integer not null check (value >= 0),
  active     boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.coupons enable row level security;
-- (sin políticas para anon => nadie lista los cupones directamente)

-- Validar UN código (para que la tienda muestre el descuento antes de pagar).
create or replace function public.validate_coupon(p_code text)
returns table(code text, kind text, value integer)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
    select c.code, c.kind, c.value
    from public.coupons c
    where upper(c.code) = upper(trim(p_code)) and c.active = true;
end;
$$;
revoke all on function public.validate_coupon(text) from public;
grant execute on function public.validate_coupon(text) to anon;

-- Crear o actualizar un cupón (desde el POS, con el secreto de publicación).
create or replace function public.upsert_coupon(
  p_secret text, p_code text, p_kind text, p_value integer, p_active boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_secret text;
begin
  select publish_secret into v_secret from public.catalog_config where id = 1;
  if v_secret is null or p_secret is null or p_secret <> v_secret then
    raise exception 'secreto invalido';
  end if;
  if p_kind not in ('percent', 'fixed') then
    raise exception 'kind invalido';
  end if;
  if trim(coalesce(p_code, '')) = '' then
    raise exception 'codigo vacio';
  end if;
  insert into public.coupons (code, kind, value, active)
  values (upper(trim(p_code)), p_kind, greatest(coalesce(p_value, 0), 0),
          coalesce(p_active, true))
  on conflict (code) do update
    set kind = excluded.kind, value = excluded.value, active = excluded.active;
end;
$$;
revoke all on function public.upsert_coupon(text, text, text, integer, boolean) from public;
grant execute on function public.upsert_coupon(text, text, text, integer, boolean) to anon;

-- Listar los cupones (POS).
create or replace function public.list_coupons(p_secret text)
returns setof public.coupons
language plpgsql
security definer
set search_path = public
as $$
declare
  v_secret text;
begin
  select publish_secret into v_secret from public.catalog_config where id = 1;
  if v_secret is null or p_secret is null or p_secret <> v_secret then
    raise exception 'secreto invalido';
  end if;
  return query select * from public.coupons order by created_at desc;
end;
$$;
revoke all on function public.list_coupons(text) from public;
grant execute on function public.list_coupons(text) to anon;

-- Borrar un cupón (POS).
create or replace function public.delete_coupon(p_secret text, p_code text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_secret text;
begin
  select publish_secret into v_secret from public.catalog_config where id = 1;
  if v_secret is null or p_secret is null or p_secret <> v_secret then
    raise exception 'secreto invalido';
  end if;
  delete from public.coupons where upper(code) = upper(trim(p_code));
end;
$$;
revoke all on function public.delete_coupon(text, text) from public;
grant execute on function public.delete_coupon(text, text) to anon;

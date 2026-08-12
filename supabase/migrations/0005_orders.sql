-- ============================================================================
-- Pedidos de la tienda en línea (pago con Mercado Pago).
-- Corre este script DESPUÉS de 0004_catalog_banners.sql, en el mismo proyecto.
--
-- Flujo: la Edge Function `create-preference` crea el pedido (status=pending) y
-- la preferencia de MP; el webhook `mp-webhook` lo marca `paid`/`failed` cuando
-- MP confirma. La tienda (anon) NUNCA lee ni escribe pedidos (traen datos del
-- cliente). El POS los lee con el secreto de publicación vía `list_orders`.
-- ============================================================================

create table if not exists public.web_orders (
  id               uuid primary key default gen_random_uuid(),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  status           text not null default 'pending', -- pending | paid | failed | cancelled
  total_cents      integer not null,
  currency         text not null default 'MXN',
  customer_name    text,
  customer_phone   text,
  delivery         boolean not null default false,
  address          text,
  notes            text,
  items            jsonb not null default '[]'::jsonb,
  mp_preference_id text,
  mp_payment_id    text
);
create index if not exists idx_web_orders_status
  on public.web_orders (status, created_at desc);

-- RLS: nadie con `anon` accede (los pedidos traen nombre/teléfono/dirección).
-- Las Edge Functions usan el service role (ignora RLS); el POS lee con secreto.
alter table public.web_orders enable row level security;
-- (sin políticas para anon => anon no lee ni escribe pedidos)

-- Lectura segura para el POS: valida el secreto de publicación (catalog_config,
-- de 0002) y devuelve los pedidos recientes. `anon` puede EJECUTARla pero
-- necesita el secreto, que no está en la tienda pública.
create or replace function public.list_orders(p_secret text, p_limit integer default 100)
returns setof public.web_orders
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
  return query
    select *
    from public.web_orders
    order by created_at desc
    limit greatest(1, least(coalesce(p_limit, 100), 500));
end;
$$;

revoke all on function public.list_orders(text, integer) from public;
grant execute on function public.list_orders(text, integer) to anon;

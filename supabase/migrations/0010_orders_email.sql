-- ============================================================================
-- Correo del pagador en los pedidos web.
-- Corre este script DESPUÉS de 0005_orders.sql, en el proyecto de la tienda.
--
-- El checkout transparente (Payment Brick / `process-payment`) pide el correo
-- del cliente porque Mercado Pago lo exige para crear el pago. Lo guardamos en
-- el pedido para que el POS pueda contactar al comprador. Es aditivo e
-- idempotente; `process-payment` funciona aunque esta columna no exista todavía.
-- ============================================================================

alter table public.web_orders
  add column if not exists customer_email text;

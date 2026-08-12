# Pago con Mercado Pago — despliegue

Todo el código ya está en el repo. Falta **desplegarlo** y poner el **secreto**
(el Access Token de Mercado Pago). Esto se hace una sola vez.

Piezas:
- `supabase/migrations/0005_orders.sql` — tabla `web_orders` + `list_orders`.
- `supabase/functions/create-preference/` — crea la preferencia de pago.
- `supabase/functions/mp-webhook/` — confirma el pago (lo llama Mercado Pago).
- Tienda: botón "Pagar con Mercado Pago" (se activa con `MP_ENABLED` en `config.js`).

## 1. Base de datos
En el **SQL Editor** de Supabase (proyecto `phyjseekbyitlntmjwwe`) corre
`supabase/migrations/0005_orders.sql`.

## 2. Credenciales de Mercado Pago
En https://www.mercadopago.com.mx/developers → **Tus integraciones** → tu app →
**Credenciales de prueba**. Copia el **Access Token** (`TEST-...`).

## 3. Desplegar las funciones
Con el CLI de Supabase (una vez: `npm i -g supabase`, luego `supabase login` y
`supabase link --project-ref phyjseekbyitlntmjwwe`):

```bash
# El secreto (NUNCA en el repo):
supabase secrets set MP_ACCESS_TOKEN="TEST-xxxxxxxx"

# Las funciones:
supabase functions deploy create-preference
supabase functions deploy mp-webhook --no-verify-jwt   # MP la llama sin JWT
```

> `SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY` ya vienen inyectados; no se ponen.

## 4. Encender el botón en la tienda
En `web-catalogo/config.js` pon `MP_ENABLED: true` y vuelve a desplegar la
tienda (`wrangler pages deploy web-catalogo --project-name shelby-caps`).

## 5. Probar (sandbox)
En la tienda: arma un carrito → **Realiza tu pedido** → **Pagar con Mercado
Pago**. Usa las **tarjetas de prueba** de MP (p. ej. Mastercard `5031 7557 3453
0604`, venc. `11/30`, CVV `123`, nombre `APRO` para aprobar). Al terminar, el
pedido aparece como `paid` en `web_orders`.

## Ver los pedidos desde el POS
`list_orders(secret)` devuelve los pedidos validando el secreto de publicación.
(La pantalla del POS para listarlos se agrega aparte.)

## Pasar a producción
Cambia el Access Token de prueba por el **productivo** (`APP_USR-...`):
`supabase secrets set MP_ACCESS_TOKEN="APP_USR-..."` y re-despliega las funciones.

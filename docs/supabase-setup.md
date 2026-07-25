# Configuración de Supabase (Fase 8 — respaldo en la nube)

El respaldo sube el **archivo completo** de la base a un bucket de Storage llamado
`backups`. Hay que crearlo (una sola vez) en **cada** proyecto: `dev` y `prod`.

## Pasos (en cada proyecto)

1. Entra a tu proyecto en https://supabase.com → **SQL Editor**.
2. Pega y ejecuta el contenido de [`supabase/migrations/0001_backups.sql`](../supabase/migrations/0001_backups.sql).
   Eso crea el bucket `backups` y las políticas para que la app (con la llave `anon`)
   pueda subir y bajar respaldos.
3. Listo. La app respalda sola tras cada venta y cada 15 minutos.

## Cómo probarlo en la tablet

1. Instala el APK (que ya trae las llaves desde `.env`).
2. Entra como admin → **Admin → Respaldo en la nube**. Debe decir "Listo para respaldar".
3. Toca **Respaldar ahora** → debe pasar a "Respaldo al día" con la hora.
   - Si sale "Error de respaldo", revisa que corriste el SQL del paso 2 en ese proyecto.
4. En **Storage → backups** del dashboard verás el archivo `boutique.sqlite`.

## Restaurar en una tablet nueva

1. Instala el APK en la tablet nueva.
2. Admin → Respaldo en la nube → **Restaurar desde la nube** → confirma.
3. **Cierra y reabre la app**: ya tendrá los datos restaurados.

## Notas

- Es **single-tenant** (una boutique, una tablet como fuente de verdad). Si hubiera
  varias tablets escribiendo, el último respaldo gana; para multi-tablet real habría
  que migrar a sincronización por filas + Supabase Auth.
- Las llaves viven en `.env` (no se sube a git). Para producción, cambia
  `SUPABASE_ENV=prod` en `.env` y reconstruye el APK.

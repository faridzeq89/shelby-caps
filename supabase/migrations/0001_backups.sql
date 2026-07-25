-- Fase 8 — Respaldo del archivo de base de datos a Supabase Storage.
-- Corre este script en el editor SQL de CADA proyecto (dev y prod).
--
-- Nota de seguridad: es una app de un solo negocio (single-tenant). La llave
-- `anon` va dentro del APK, así que estas políticas dan acceso al bucket a quien
-- tenga esa llave. Aceptable para una boutique con una tablet. Si más adelante
-- hay varias tablets o se quiere endurecer, se migra a Supabase Auth + RLS por
-- negocio.

-- 1) Bucket privado para los respaldos.
insert into storage.buckets (id, name, public)
values ('backups', 'backups', false)
on conflict (id) do nothing;

-- 2) Permitir a la llave anon leer/escribir SOLO el bucket de respaldos.
create policy "boutique anon backups select"
  on storage.objects for select to anon
  using (bucket_id = 'backups');

create policy "boutique anon backups insert"
  on storage.objects for insert to anon
  with check (bucket_id = 'backups');

create policy "boutique anon backups update"
  on storage.objects for update to anon
  using (bucket_id = 'backups')
  with check (bucket_id = 'backups');

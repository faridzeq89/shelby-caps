-- ============================================================================
-- Cuenta del negocio (login por correo) + respaldo por cuenta.
-- Corre en el proyecto de la tienda. Cada usuario autenticado respalda su base
-- en su propia carpeta `u/<uid>/` dentro del bucket `backups`, y solo puede
-- leer/escribir esa carpeta. Así, entrar con la cuenta en otro equipo baja los
-- datos de ESA cuenta y nadie más los ve. El respaldo global sin cuenta
-- (`boutique.sqlite`, políticas anon de 0001) se conserva para retrocompat.
-- ============================================================================

-- Cada política se re-crea (drop+create) para ser idempotente.
drop policy if exists "account backup select" on storage.objects;
create policy "account backup select" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'backups'
    and (storage.foldername(name))[1] = 'u'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

drop policy if exists "account backup insert" on storage.objects;
create policy "account backup insert" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'backups'
    and (storage.foldername(name))[1] = 'u'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

drop policy if exists "account backup update" on storage.objects;
create policy "account backup update" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'backups'
    and (storage.foldername(name))[1] = 'u'
    and (storage.foldername(name))[2] = auth.uid()::text
  )
  with check (
    bucket_id = 'backups'
    and (storage.foldername(name))[1] = 'u'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

drop policy if exists "account backup delete" on storage.objects;
create policy "account backup delete" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'backups'
    and (storage.foldername(name))[1] = 'u'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

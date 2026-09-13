-- 0014: permitir que la CUENTA DEL NEGOCIO publique fotos y banners.
--
-- Las fotos de producto y los banners se suben a Storage (bucket `catalog`)
-- desde el POS. Las políticas del bucket (0003) se escribieron solo `to anon`,
-- cuando el POS hablaba con Supabase siempre como `anon`.
--
-- Al agregar la "Cuenta del negocio" (acceso multi-dispositivo), el POS con
-- sesión iniciada sube como rol `authenticated`, que esas políticas NO cubrían:
-- Storage devolvía 403 ("new row violates row-level security policy"). Las fotos
-- de producto ya subidas se omiten por huella, así que no fallaban; pero los
-- banners SIEMPRE se re-suben, así que nunca llegaban a la tienda y `catalog_banners`
-- quedaba vacía (la tienda caía a los banners de ejemplo).
--
-- Se amplían las tres políticas del bucket `catalog` a `anon` + `authenticated`.
-- No es regresión: el bucket ya era escribible por `anon` (catálogo público) y
-- los únicos `authenticated` son los dueños del negocio.

drop policy if exists "catalog anon read" on storage.objects;
drop policy if exists "catalog read" on storage.objects;
create policy "catalog read"
  on storage.objects for select to anon, authenticated
  using (bucket_id = 'catalog');

drop policy if exists "catalog anon insert" on storage.objects;
drop policy if exists "catalog insert" on storage.objects;
create policy "catalog insert"
  on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'catalog');

drop policy if exists "catalog anon update" on storage.objects;
drop policy if exists "catalog update" on storage.objects;
create policy "catalog update"
  on storage.objects for update to anon, authenticated
  using (bucket_id = 'catalog')
  with check (bucket_id = 'catalog');

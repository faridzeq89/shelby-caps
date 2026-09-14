import 'package:supabase_flutter/supabase_flutter.dart';

/// Config PÚBLICA del backend de la tienda (proyecto Supabase dedicado).
///
/// La llave `anon` es pública por diseño: solo permite LEER el catálogo y subir
/// al bucket público `catalog`; las escrituras a las tablas pasan por
/// `publish_catalog`, que valida un secreto aparte. Es la misma llave que va en
/// `web-catalogo/config.js` y como último recurso en `main.dart`.
///
/// Se usa para publicar el catálogo **como `anon`** aunque el dueño tenga la
/// Cuenta del negocio iniciada: el bucket `catalog` solo acepta escrituras del
/// rol `anon`, así que publicar con la sesión (rol `authenticated`) daba 403 y
/// los banners nunca subían.
const storeSupabaseUrl = 'https://phyjseekbyitlntmjwwe.supabase.co';
const storeSupabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBoeWpzZWVrYnlpdGxudG1qd3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY0MDg4MzMsImV4cCI6MjEwMTk4NDgzM30.0xbMKEAN6cmzua3YPeHwOFx5rAapMcGHOk8LJrooY20';

SupabaseClient? _publishAnonClient;

/// Cliente con el que se PUBLICA a la tienda (subidas a Storage + RPC).
///
/// Debe ir como rol `anon`: el bucket `catalog` solo permite escribir a `anon`,
/// y con la Cuenta del negocio iniciada el cliente global es `authenticated`,
/// que Storage rechaza (403 "row-level security policy"). Si no hay sesión, el
/// cliente global ya es anon y se reusa; si la hay, se usa uno dedicado (creado
/// una sola vez).
SupabaseClient storePublishClient() {
  final c = Supabase.instance.client;
  if (c.auth.currentUser == null) return c;
  return _publishAnonClient ??=
      SupabaseClient(storeSupabaseUrl, storeSupabaseAnonKey);
}

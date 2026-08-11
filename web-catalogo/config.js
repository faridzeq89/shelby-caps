// Configuración de la tienda web. La llave `anon` es PÚBLICA por diseño
// (solo permite LEER el catálogo; RLS bloquea escrituras). No pongas aquí
// service role ni secretos.
window.CATALOGO_CONFIG = {
  SUPABASE_URL: "https://phyjseekbyitlntmjwwe.supabase.co",
  SUPABASE_ANON:
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBoeWpzZWVrYnlpdGxudG1qd3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY0MDg4MzMsImV4cCI6MjEwMTk4NDgzM30.0xbMKEAN6cmzua3YPeHwOFx5rAapMcGHOk8LJrooY20",
  // Nombre de la tienda (se ajusta en la fase de look & feel).
  SHOP_NAME: "SHELBY CAPS",
};

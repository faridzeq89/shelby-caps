// Configuración de la tienda web. La llave `anon` es PÚBLICA por diseño
// (solo permite LEER el catálogo; RLS bloquea escrituras). No pongas aquí
// service role ni secretos — el secreto de publicación vive solo en el POS.
window.CATALOGO_CONFIG = {
  SUPABASE_URL: "https://phyjseekbyitlntmjwwe.supabase.co",
  SUPABASE_ANON:
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBoeWpzZWVrYnlpdGxudG1qd3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY0MDg4MzMsImV4cCI6MjEwMTk4NDgzM30.0xbMKEAN6cmzua3YPeHwOFx5rAapMcGHOk8LJrooY20",

  SHOP_NAME: "SHELBY CAPS",
  ADDRESS: "Calle Monterrey 455 Col. Rdz, Reynosa",

  // Horario por día (0 = domingo … 6 = sábado). `null` = cerrado ese día.
  // Con esto la barra dice "Abierto" o "Abre mar, 11:00 a. m. - 7:00 p. m.".
  OPENING_HOURS: {
    0: null,
    1: null,
    2: ["11:00", "19:00"],
    3: ["11:00", "19:00"],
    4: ["11:00", "19:00"],
    5: ["11:00", "19:00"],
    6: ["11:00", "19:00"],
  },
};

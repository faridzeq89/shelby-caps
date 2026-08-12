// Configuración de la tienda web. La llave `anon` es PÚBLICA por diseño
// (solo permite LEER el catálogo; RLS bloquea escrituras). No pongas aquí
// service role ni secretos — el secreto de publicación vive solo en el POS.
window.CATALOGO_CONFIG = {
  SUPABASE_URL: "https://phyjseekbyitlntmjwwe.supabase.co",
  SUPABASE_ANON:
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBoeWpzZWVrYnlpdGxudG1qd3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY0MDg4MzMsImV4cCI6MjEwMTk4NDgzM30.0xbMKEAN6cmzua3YPeHwOFx5rAapMcGHOk8LJrooY20",

  SHOP_NAME: "SHELBY CAPS",
  ADDRESS: "Calle Monterrey 455 Col. Rdz, Reynosa",

  // WhatsApp de la tienda para recibir pedidos. Solo dígitos, con lada de país
  // (52 = México) + los 10 dígitos. Se usa para armar la liga wa.me con el
  // pedido prellenado.
  WHATSAPP: "528997034922",

  // Pago con Mercado Pago. Ponlo en `true` SOLO cuando ya estén desplegadas las
  // Edge Functions (create-preference / mp-webhook) y el secreto MP_ACCESS_TOKEN
  // en Supabase. Mientras esté en `false`, el botón "Pagar con tarjeta" no
  // aparece y la tienda sigue tomando pedidos por WhatsApp.
  MP_ENABLED: false,

  // Foto de portada del catálogo (arriba de todo). Vacío = sin portada.
  COVER: "img/portada.svg",

  // Banners promocionales que rotan solos, estilo Uber Eats. NO son productos:
  // son solo imágenes. `link` es opcional (a dónde manda al tocarlo).
  BANNERS: [
    { image: "img/banner-1.svg", alt: "Mayoreo desde 6 piezas" },
    { image: "img/banner-2.svg", alt: "Gorras personalizadas" },
    { image: "img/banner-3.svg", alt: "Servicio de limpieza de gorras" },
  ],

  // Segundos que dura cada banner antes de pasar al siguiente.
  BANNER_SECONDS: 5,

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

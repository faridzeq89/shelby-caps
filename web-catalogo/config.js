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

  // Pago con Mercado Pago (checkout transparente / Payment Brick: el cliente
  // paga con tarjeta SIN salir de la tienda). Ponlo en `true` SOLO cuando ya
  // esté desplegada la Edge Function `process-payment` y el secreto
  // MP_ACCESS_TOKEN en Supabase. En `false`, el botón "Pagar con tarjeta" no
  // aparece y la tienda sigue tomando pedidos por WhatsApp.
  MP_ENABLED: true,

  // Public Key de Mercado Pago (PÚBLICA por diseño: va en el navegador para que
  // el Payment Brick tokenice la tarjeta). NO es el Access Token (ese es secreto
  // y vive en Supabase). `TEST-...` = pruebas; `APP_USR-...` = producción.
  MP_PUBLIC_KEY: "APP_USR-b2e12a74-2568-4038-89b4-1af011269815",

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

  // Información de envíos y compra (preguntas frecuentes). Se edita aquí sin
  // tocar el HTML ni el JS. El enlace para verla aparece solo si esta lista
  // trae algo — vaciarla (`[]`) la oculta sin dejar una pantalla rota.
  SHIPPING: {
    // Aviso destacado arriba de las preguntas. Vacío = sin aviso.
    NOTICE: "¡Los envíos salen el mismo día de tu pago! Antes de las 4:00 p. m.",
    FAQ: [
      {
        q: "¿Qué paquetería utilizamos?",
        a: "Todos nuestros envíos son realizados por FedEx, Estafeta o DHL.",
      },
      {
        q: "¿Cuánto tiempo tarda en llegar mi paquete?",
        a: "Realizamos envíos express: tardan de 1 a 3 días dependiendo la " +
          "zona y el código postal.",
      },
      {
        q: "¿Aceptamos pago contra entrega?",
        a: "No. Para mayor seguridad y confianza aceptamos pago por medio " +
          "de Mercado Pago.",
      },
      {
        q: "¿Se puede realizar videollamada?",
        a: "Sí. Podemos hacer una videollamada, para más confianza y para " +
          "que puedas escoger tus piezas.",
      },
      {
        q: "¿Tienen referencias de ventas?",
        a: "Contamos con cientos de referencias vía WhatsApp.",
      },
    ],
  },
};

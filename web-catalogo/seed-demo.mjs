/* Publica un CATÁLOGO FALSO de prueba en Supabase, llamando a la misma función
 * `publish_catalog` que usa el POS. Sirve para ver la tienda funcionando de
 * punta a punta antes de que el cliente cargue su inventario real.
 *
 * Uso:
 *   node seed-demo.mjs <secreto-de-publicacion>
 *
 * OJO: `publish_catalog` REEMPLAZA el catálogo publicado (hace TRUNCATE). Al
 * publicar desde el POS, estos datos falsos se van y quedan los reales.
 *
 * Las fotos son SVG generados aquí mismo (data URI): no dependen de internet
 * ni de Storage, así que la prueba funciona aunque el bucket esté vacío.
 */
import { readFileSync } from "node:fs";

const secret = process.argv[2];
if (!secret) {
  console.error("Falta el secreto: node seed-demo.mjs <secreto-de-publicacion>");
  process.exit(1);
}

// Reusa la URL y la llave de la tienda (config.js) para no duplicarlas.
const cfgSrc = readFileSync(new URL("./config.js", import.meta.url), "utf8");
const URL_ = cfgSrc.match(/SUPABASE_URL:\s*"([^"]+)"/)[1];
const ANON = cfgSrc.match(/SUPABASE_ANON:\s*\n?\s*"([^"]+)"/)[1];

/** Gorra dibujada en SVG, con los colores de cada modelo y la vista indicada. */
function capSvg(base, accent, view, label) {
  const views = {
    frente: `<path d="M40 150 Q40 70 128 70 Q216 70 216 150 Z" fill="${base}"/>
             <path d="M36 150 Q128 132 220 150 Q220 178 128 178 Q36 178 36 150 Z" fill="${accent}"/>
             <circle cx="128" cy="74" r="7" fill="${accent}"/>
             <text x="128" y="126" font-family="sans-serif" font-size="30" font-weight="700"
                   fill="${accent}" text-anchor="middle">${label}</text>`,
    perfil: `<path d="M60 152 Q60 74 132 74 Q204 74 204 152 Z" fill="${base}"/>
             <path d="M204 152 Q244 154 250 170 Q200 178 132 176 Q60 176 60 152 Z" fill="${accent}"/>
             <path d="M132 74 L132 152" stroke="${accent}" stroke-width="4"/>`,
    atras: `<path d="M46 152 Q46 74 128 74 Q210 74 210 152 Z" fill="${base}"/>
            <rect x="104" y="120" width="48" height="34" rx="6" fill="${accent}"/>
            <path d="M46 152 Q128 160 210 152" stroke="${accent}" stroke-width="6" fill="none"/>`,
    detalle: `<circle cx="128" cy="128" r="72" fill="${base}"/>
              <text x="128" y="142" font-family="sans-serif" font-size="42" font-weight="800"
                    fill="${accent}" text-anchor="middle">${label}</text>`,
  };
  const svg =
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256">` +
    `<rect width="256" height="256" fill="#f2f2f2"/>${views[view]}` +
    `<text x="128" y="238" font-family="sans-serif" font-size="13" fill="#9a9a9a"` +
    ` text-anchor="middle">${view}</text></svg>`;
  return "data:image/svg+xml;utf8," + encodeURIComponent(svg);
}

// Catálogo de prueba: nombres, precios y agotados calcados del catálogo real
// del cliente, para que la vista se sienta igual de poblada.
const CAPS = [
  ["17 OHTANI", "New Era G5", 60000, 6, "#1b2a4a", "#c8a24a", "17"],
  ["3 CRUCES / PERSONALIZADA", "Personalizado", 70000, 3, "#111", "#e8e8e8", "✝"],
  ["ADIDAS", "Réplica Premium", 70000, 4, "#c8b28a", "#5a4632", "A"],
  ["ADIDAS BLACK", "Réplica Premium", 70000, 5, "#141414", "#fff", "A"],
  ["ALO AZUL CLARO", "Originales", 85000, 2, "#7fb3d5", "#fff", "alo"],
  ["ALO AZUL MARINO", "Originales", 85000, 0, "#1f3864", "#fff", "alo"],
  ["ALO BLANCA", "Originales", 85000, 3, "#f2f2f2", "#333", "alo"],
  ["ALO NEGRA", "Originales", 85000, 4, "#141414", "#fff", "alo"],
  ["AMIRI CRYSTAL GAMUZA", "Réplica Premium", 95000, 0, "#6b5b73", "#e6d7f2", "AM"],
  ["AMIRI GREY / BIGGBOSS", "Réplica Premium", 95000, 0, "#8a8a8a", "#222", "AM"],
  ["ANGELS NEGRA", "New Era G5", 60000, 7, "#141414", "#c8102e", "A"],
  ["ASTROS NARANJA/NEGRO", "New Era G5", 60000, 5, "#eb6e1f", "#0f1e2e", "H"],
  ["ATLANTA", "New Era G5", 60000, 4, "#13274f", "#ce1141", "A"],
  ["BILLS", "New Era G5", 60000, 6, "#00338d", "#c60c30", "B"],
  ["BOSS", "Réplica Premium", 70000, 0, "#141414", "#fff", "BOSS"],
  ["BOSTON CAPS FANS", "Personalizado", 130000, 2, "#141414", "#d6b25e", "B"],
  ["BOSTON ROJA CORAZÓN", "Personalizado", 130000, 0, "#bd3039", "#fff", "♥"],
  ["BULLS AZUL", "New Era G5", 60000, 5, "#1d428a", "#ce1141", "B"],
  ["BY CHAVALON", "Personalizado", 150000, 2, "#141414", "#c8a24a", "CH"],
  ["DODGERS AZUL", "New Era G5", 60000, 8, "#005a9c", "#fff", "LA"],
  ["LLAVERO GORRA", "Accesorios", 12000, 20, "#8a6d3b", "#f0e6d2", "🧢"],
  ["NY YANKEES NEGRA", "New Era G5", 60000, 9, "#0c2340", "#fff", "NY"],
  ["RAIDERS NEGRA", "New Era G5", 60000, 6, "#0b0b0b", "#a5acaf", "R"],
  ["TEXAS AZUL MARINO", "New Era G5", 60000, 0, "#003278", "#c0111f", "T"],
];

const DESCRIPCIONES = {
  "ADIDAS": "Gorra beige y cafe de tela con visera curva",
  "ADIDAS BLACK": "Gorra negra de tela con logo blanco y visera curva",
  "ALO BLANCA": "Gorra blanca malla trasera visera curva",
  "ALO NEGRA": "Gorra negra de malla con visera curva",
  "BOSS": "Gorra negra de tela, visera curva, logo BOSS al frente",
  "BOSTON CAPS FANS": "Gorra negra de tela con aplique brillante y visera curva",
  "BY CHAVALON": "Gorra negra de tela con visera curva y bordado",
};

const products = [];
const variants = [];
const tiers = [];
const images = [];

CAPS.forEach(([name, category, price, stock, base, accent, label], i) => {
  const id = i + 1;
  products.push({
    id,
    name,
    brand: category === "Accesorios" ? null : "Shelby",
    category,
    description: DESCRIPCIONES[name] || null,
    base_price_cents: price,
    tax_rate_bps: 1600,
    active: true,
  });

  // Talla única en gorras (son ajustables); el llavero tampoco lleva talla.
  variants.push({
    id,
    product_id: id,
    sku: "SC-" + String(id).padStart(4, "0"),
    size: null,
    color: null,
    price_cents: price,
    stock,
    active: true,
  });

  // Mayoreo en los modelos de línea, como el POS lo publica.
  if (category === "New Era G5" || category === "Réplica Premium") {
    tiers.push({ product_id: id, min_qty: 6, price_cents: Math.round(price * 0.85) });
    tiers.push({ product_id: id, min_qty: 12, price_cents: Math.round(price * 0.75) });
  }

  // Varias vistas por gorra: eso es justo lo que el cliente pidió poder subir.
  const vistas = category === "Accesorios"
    ? ["detalle"]
    : ["frente", "perfil", "atras", "detalle"];
  vistas.forEach((v, pos) => {
    images.push({ product_id: id, url: capSvg(base, accent, v, label), position: pos });
  });
});

async function publish(payload) {
  return fetch(URL_ + "/rest/v1/rpc/publish_catalog", {
    method: "POST",
    headers: {
      apikey: ANON,
      Authorization: "Bearer " + ANON,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });
}

const base = {
  p_secret: secret,
  p_products: products,
  p_variants: variants,
  p_tiers: tiers,
};

let withImages = true;
let res = await publish({ ...base, p_images: images });

// Si todavía no se corrió 0003_catalog_images.sql, la función de 5 argumentos
// no existe (PostgREST responde PGRST202). Publicamos sin fotos en vez de fallar.
if (!res.ok && res.status === 404) {
  withImages = false;
  res = await publish(base);
}

if (!res.ok) {
  console.error("Falló la publicación:", res.status, await res.text());
  process.exit(1);
}

console.log(
  `Catálogo de prueba publicado: ${products.length} gorras, ` +
  `${tiers.length} escalones de mayoreo, ` +
  `${CAPS.filter((c) => c[3] === 0).length} agotadas.`
);
console.log(
  withImages
    ? `Fotos: ${images.length} (varias vistas por gorra).`
    : "SIN fotos: corre supabase/migrations/0003_catalog_images.sql y vuelve a ejecutar."
);

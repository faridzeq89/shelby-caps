# Tienda web (catálogo público)

Sitio **estático** phone-first que muestra el catálogo publicado por el POS.
Calca el catálogo que el cliente ya usaba en Treinta: fondo blanco, foto
cuadrada mandando, dos columnas en celular, chips de categoría, orden y vista
en cuadrícula o lista.

- Lee de Supabase con la llave `anon` (**pública**, solo lectura; RLS bloquea
  escrituras). El catálogo lo publica el POS (Admin → Catálogo web).
- **Varias fotos por producto**: la ficha trae galería deslizable con puntos.
  La posición 0 es la portada (la que sale en la rejilla y en el POS).
- El carrito replica el **mayoreo** del POS: el precio baja al alcanzar el
  escalón contando la cantidad surtida entre variantes del mismo producto.
- Sin build ni dependencias: `index.html` + `styles.css` + `app.js` + `config.js`.
- El **cobro (Mercado Pago)** se enchufa en la fase #8: "Continuar al pago" es
  todavía un marcador.

## Configurar

`config.js` lleva la URL del proyecto, la llave `anon`, el nombre de la tienda,
la dirección y el horario por día (con eso la barra dice "Abierto" o "Abre mar,
11:00 a. m. - 7:00 p. m.").

El **acento** es una variable de CSS: `--accent` en `styles.css`. Hoy es el
amarillo del catálogo original; para que la tienda se vea como el POS se cambia
esa línea al latón `#9C7A2C` y listo.

## Probar localmente

```bash
npx --yes serve web-catalogo -l 8099
# abre http://127.0.0.1:8099
```

## Catálogo falso de prueba

Publica 24 gorras con precios, agotados, mayoreo y varias vistas por modelo
(SVG generados, sin depender de internet):

```bash
node seed-demo.mjs <secreto-de-publicacion>
```

**Ojo:** `publish_catalog` REEMPLAZA el catálogo publicado. Al publicar desde el
POS, estos datos falsos se van y quedan los reales. Requiere haber corrido
`supabase/migrations/0003_catalog_images.sql`; sin eso publica sin fotos y lo
avisa en la salida.

## Publicar en Cloudflare Pages (.pages.dev)

```bash
npx wrangler pages deploy web-catalogo --project-name shelby-caps
```

O conectando el repo en el panel de Cloudflare Pages con el directorio de
salida `web-catalogo/` (sin comando de build).

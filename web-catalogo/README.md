# Tienda web (catálogo público)

Sitio **estático** phone-first que muestra el catálogo del POS y arma un carrito
con **mayoreo** (mismo comportamiento que el POS: el precio baja al alcanzar el
umbral, contando cantidad **surtida** entre variantes del mismo producto).

- Lee de Supabase con la llave `anon` (**pública**, solo lectura; RLS bloquea
  escrituras). El catálogo lo publica el POS (Admin → Catálogo web).
- Sin build ni dependencias: `index.html` + `styles.css` + `app.js` + `config.js`.
- El **cobro (Mercado Pago)** se enchufa en la fase #8: el botón "Continuar al
  pago" hoy es un placeholder.

## Configurar

Edita `config.js` con la URL del proyecto, la llave `anon` y el nombre de la tienda.

## Probar localmente

```bash
cd web-catalogo
python -m http.server 8099
# abre http://127.0.0.1:8099
```

## Publicar en Cloudflare Pages (.pages.dev)

Cuando se decida publicar (hoy NO se publica nada):

```bash
# con wrangler (Cloudflare)
npx wrangler pages deploy web-catalogo --project-name shelby-caps
```

O conectando el repo en el panel de Cloudflare Pages y apuntando el directorio
de salida a `web-catalogo/` (sin comando de build).

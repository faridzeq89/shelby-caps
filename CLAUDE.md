# POS Boutique — CLAUDE.md

Memoria del proyecto entre sesiones. **Actualizar al cerrar cada fase.**

## Qué es
Punto de venta para **boutique de ropa** (retail), en tablet Android. Venta directa
por mostrador con escaneo de código de barras, variantes talla×color, inventario por
SKU, apartados, devoluciones/cambios y corte de caja.

## Stack (decidido)
- **Flutter** (app Android nativa) + **Drift/SQLite local** como fuente de verdad.
- **Local-first**: la tablet opera sin internet; la nube es respaldo, no dependencia.
- **Supabase** como respaldo/sincronización en la nube (dos proyectos: `dev` y `prod`).
- Impresión de ticket **ESC/POS** reutilizando lo probado en el POS Maraco (restaurante).
- Autenticación **por PIN + roles** (admin / manager / cashier). Email/password solo admin
  para el login de respaldo en la nube.
- Proyecto Flutter: package `pos_boutique`, applicationId **`com.boutique.pos_boutique`**,
  solo plataforma Android. Estado con `provider`, base local con `drift`.

> Nota de arquitectura vs. el documento original: el doc apuntaba a React PWA + Supabase
> (verdad en la nube, offline como fase difícil al final). Aquí es al revés: Flutter es
> offline por diseño, la Fase 8 es "sincronización a la nube", y la seguridad la impone
> la app (roles/PIN), no la RLS de Postgres (esa solo protege el espejo de respaldo).

## Convenciones (no negociables)
- **Dinero en centavos enteros** (`*_cents INTEGER`). Nunca `double`/`float`.
- **Cantidades de inventario en enteros con signo** en un **ledger append-only**
  (`inventory_movements`), NUNCA una columna `stock` editable. El stock es una consulta.
- `inventory_movements` **no se actualiza ni se borra** — ni admin. Es un libro mayor.
- **UUID de venta generado en el cliente** (idempotencia: un reintento no duplica).
- **Folios con prefijo de dispositivo** (`T1-000123`) para no colisionar entre tablets.
- Nombres de tablas/columnas en **inglés, snake_case**. Enums explícitos.
- IVA **incluido** en el precio; se desglosa hacia atrás. `tax_rate` **por producto**.
- Redondeo de IVA **a nivel ticket** (desglosar una vez), no por línea.
- Zona horaria **America/Mexico_City**; el "día de operación" lo define el corte de caja.
- Toda migración de esquema en archivos versionados. Si no está en el repo, no existe.
- **Commit + tag al cerrar cada fase** (`fase-3-catalogo`).
- **Una fase por sesión.** No empezar la siguiente en la misma sesión que se cerró una.

## Estado de fases
- [x] **Fase 0 — Decisiones** (este documento + `docs/decisiones.md`). Cerrada 2026-07-25,
      sin decisiones abiertas (los 5 puntos de negocio ya confirmados).
- [x] **Fase 1 — Fundación**. Cerrada 2026-07-25. Flutter (Android) + Drift + login por PIN
      con roles + gating de admin + layout tablet. 3 pruebas verdes, `flutter analyze` limpio.
      Admin inicial: PIN **1234**, obliga a cambiarlo al primer login. Pendiente de Fase 1 que
      se movió: el respaldo/login Supabase se hará junto con la Fase 8 (sincronización nube).
- [x] **Fase 2 — Esquema, seguridad de app y semillas**. Cerrada 2026-07-25. Esquema
      completo en Drift (schemaVersion 2): catálogo, ledger `inventory_movements` append-only,
      ventas/pagos/apartados/notas de crédito, clientes, caja, auditoría, conteos, folios.
      Vista `variant_stock` (on_hand/reserved/available) + triggers de inmutabilidad del ledger.
      Seguridad por rol en repos (`Permissions`, `CatalogRepository`, `InventoryRepository`).
      Semilla de ~12 productos con matriz talla×color, códigos `MB`, costos y stock inicial.
      9 pruebas verdes. Sin APK (fase sin UI nueva). RLS de Supabase pendiente para Fase 8.
- [~] **Fase 3 — Catálogo admin**. Núcleo cerrado 2026-07-25 (con APK). CRUD de categorías/
      productos, **generador de matriz de variantes** (talla×color con códigos `MB` y stock
      inicial), alta de código de proveedor, **resolución por escaneo** (código→variante),
      edición de precios/costos con auditoría, **etiquetas PDF (Code128) + generación ZPL**.
      14 pruebas verdes; migración v1→v2 verificada. **Pendiente de Fase 3: importación
      CSV/Excel** (hueco #12) y envío real a etiquetadora ZPL (depende de hardware).
- [x] **Fase 4 — Venta camino feliz**. Cerrada 2026-07-25 (con APK). `SalesRepository.checkout`:
      venta + líneas + pago + movimientos `sale` (stock −qty) en UNA transacción; folio con
      prefijo de dispositivo; IVA desglosado por línea. UI `lib/features/sales/`: pantalla de
      venta (campo escaneo/búsqueda HID, carrito con +/−, totales), cobro en efectivo con cambio
      y atajos, ticket de regalo (sin precios), ticket PDF (rollo 80mm). Venta se guarda ANTES
      de imprimir (si falla la impresión, la venta persiste). Botón "Vender" en home para todos.
      19 pruebas verdes. ESC/POS térmico real pendiente de hardware (como el ZPL).
- [~] **Fase 5 — Pagos múltiples, descuentos y corte de caja**. Núcleo cerrado 2026-07-25
      (con APK). Esquema v3: tabla `cash_movements`. `checkout` acepta **pagos divididos**
      (efectivo/tarjeta/transferencia) y **descuento por venta** (reparto proporcional, IVA por
      línea, auditado); autorización por **PIN de gerente** sobre 15%. `cancelSale` (gerente/
      admin): no borra, marca `cancelled`, devuelve stock (`returned`) y audita. `CashSessionRepository`
      + pantalla **Corte de caja**: abrir con fondo, retiros/depósitos, resumen en vivo, ventas del
      turno con cancelación, cierre con arqueo (esperado vs contado + diferencia). Migración v2→v3
      probada. 24 pruebas verdes. **Pendiente de Fase 5: descuento por línea individual.**
- [x] **Fase 6 — Devoluciones y cambios**. Cerrada 2026-07-25 (con APK). `ReturnsRepository`:
      buscar venta por folio, `returnableLines` (valida lo ya devuelto), `processReturn`
      (reembolso efectivo con autorización de gerente, o nota de crédito; movimientos `returned`;
      pieza dañada = returned + adjustment que la saca de stock vendible), `processExchange`
      (devolución + venta nueva en UNA transacción; el crédito de lo devuelto se aplica y se
      cobra/acredita la diferencia). Selector de variante extraído a `variant_picker.dart`
      (compartido venta/cambio). Pantalla Devoluciones desde la barra de Venta. 29 pruebas verdes.
- [ ] Fase 7 — Apartados
- [ ] Fase 8 — Sincronización/respaldo en la nube y reconciliación (era "offline" en el doc)
- [ ] Fase 9 — Inventario operativo (recepción, ajustes, conteo físico)
- [ ] Fase 10 — Reportes (+ ventas por vendedor)
- [ ] Fase 11 — Producción (firma APK, respaldo, monitoreo, aviso de privacidad, capacitación)

## Orden mínimo para operar
Fases 1 → 2 → 3 → 4 → 5 dan una tienda vendiendo con corte de caja. La 6 y 7 se piden la
primera semana. La 8 (respaldo robusto) es la red de seguridad.

## Documentos
- `docs/decisiones.md` — las decisiones de Fase 0 con su justificación y los TBD.
- `docs/plan-fases.md` — el plan de construcción por fases, adaptado a Flutter.

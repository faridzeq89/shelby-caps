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
      14 pruebas verdes; migración v1→v2 verificada. **Importación CSV/Excel RESUELTA**
      (backlog 2026-07-26, ver abajo). Pendiente: envío real a etiquetadora ZPL (depende de hardware).
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
      probada. 24 pruebas verdes. **Descuento por línea individual RESUELTO** (backlog 2026-07-26).
- [x] **Fase 6 — Devoluciones y cambios**. Cerrada 2026-07-25 (con APK). `ReturnsRepository`:
      buscar venta por folio, `returnableLines` (valida lo ya devuelto), `processReturn`
      (reembolso efectivo con autorización de gerente, o nota de crédito; movimientos `returned`;
      pieza dañada = returned + adjustment que la saca de stock vendible), `processExchange`
      (devolución + venta nueva en UNA transacción; el crédito de lo devuelto se aplica y se
      cobra/acredita la diferencia). Selector de variante extraído a `variant_picker.dart`
      (compartido venta/cambio). Pantalla Devoluciones desde la barra de Venta. 29 pruebas verdes.
- [x] **Fase 7 — Apartados**. Cerrada 2026-07-25 (con APK). `LayawayRepository`: cliente mínimo,
      `createLayaway` (venta status layaway, anticipo 30% mínimo, reserva con movimientos `reserve`
      — la pieza sigue en on_hand pero no disponible), `addPayment` (abonos), `settle` (release+sale,
      status completed, ticket con todos los pagos), `expireOverdue` (libera reservas, lo pagado →
      nota de crédito, terms expired). Pantalla Apartados (lista con por vencer/vencido, nuevo
      apartado, detalle con abonos/liquidar/reimprimir) desde la barra de Venta. Vencimiento: manual
      con "Procesar vencidos" (no hay cron local). Comprobante PDF. 32 pruebas verdes.
- [~] **Fase 8 — Respaldo en la nube (Supabase)**. Código cerrado 2026-07-25 (con APK).
      Respaldo del archivo completo de la base (VACUUM INTO) a Supabase Storage bucket `backups`,
      ruta fija `boutique.sqlite` (single-tenant → restaurar en tablet nueva). `CloudBackupService`
      (estado idle/syncing/ok/error, tras cada venta + periódico 15 min + manual, restaurar).
      Pantalla Admin → Respaldo en la nube. Config en `.env` (gitignored) DEV/PROD, `flutter_dotenv`
      + `supabase_flutter`. **FALTA que el dueño corra `supabase/migrations/0001_backups.sql` en
      cada proyecto** (bucket + políticas anon) — ver `docs/supabase-setup.md`. Verificación
      end-to-end en dispositivo (no testeable desde CI). **Reporte de reconciliación RESUELTO**
      (backlog 2026-07-26).
- [x] **Fase 9 — Inventario operativo**. Cerrada 2026-07-25 (con APK). Esquema v4:
      `variants.min_stock` (punto de reorden por variante) + migración v3→v4 idempotente
      (`_addMinStockIfMissing`). `InventoryRepository` ampliado: `receiveBatch` (movimientos
      `receipt`, opción de actualizar costo), `adjust` (movimiento `adjustment` con motivo
      obligatorio — merma/dañado/robo/corrección — gerente/admin o PIN de gerente), conteo
      físico sobre `stock_counts`/`stock_count_lines` (crear/capturar/ver diferencias/aplicar
      en lote como movimientos `count`/cancelar), y stock bajo (`lowStockVariants`/`lowStockCount`
      usando disponible = on_hand − reservado; default global en `app_settings.low_stock_default`).
      UI en `lib/features/inventory/`: hub + recepción + ajuste + conteo + stock bajo; enganchada
      desde la barra de Venta (campana con badge + icono de inventario) y tarjeta en Admin. Todo
      respeta el ledger append-only y audita. 40 pruebas verdes (9 nuevas: 8 de inventario +
      migración v4). **Traspasos entre ubicaciones diferidos** hasta que exista 2ª sucursal.
- [x] **Fase 10 — Reportes**. Cerrada 2026-07-25 (con APK). `ReportsRepository` (solo lectura,
      SQL de agregación sobre ventas/ledger): `periodSummary` (con comparativo vs periodo anterior),
      `variantSales` (top y desglose talla/color), `marginByProduct` (último costo), `deadStock`
      (existencia sin venta en N días), `cashierVariances` (arqueos), `returnRates`, `salesBySalesperson`
      (cae al cajero si no hay vendedor). UI `lib/features/reports/`: `reports_screen` (selector de
      periodo Hoy/7/30/60, tarjeta de resumen, detalle por reporte en DataTable) + `report_export`
      (CSV con BOM UTF-8, compartido vía `Printing.sharePdf`). Enlazado desde Admin. 43 pruebas verdes
      (3 nuevas). Sin cambio de esquema (no requiere build_runner).
- [~] **Fase 11 — Producción**. Documentación y config sin secretos preparadas 2026-07-25.
      Pendiente del dueño: DSN de Sentry (requiere sus credenciales; ver `docs/produccion.md`).
      La firma release quedó operativa en la Fase 12 (keystore en `android/boutique-release.jks`;
      se corrigió la ruta de `storeFile` en `build.gradle.kts` para resolver contra `android/`).
- [x] **Fase 12 — Rediseño visual + cámara + catálogo de prueba**. Cerrada 2026-07-26 (con APK
      release firmado, 81.8 MB). Esquema **v5**: `products.image_path` (ruta local de la foto
      optimizada o clave de asset `assets/...`) + migración v4→v5 idempotente (`_addImagePathIfMissing`,
      `onUpgrade` refactorizado a pasos aditivos). **ImageService** (`lib/services/image_service.dart`):
      optimiza fotos a JPEG ≤1000px calidad 82 (~30-50 KB), guarda en `product_images/`, borra;
      helper `productImageProvider` (AssetImage vs FileImage). **Cámara escáner** (`mobile_scanner`,
      `lib/features/scan/scanner_screen.dart`, on-device/offline) en venta y en el selector de
      inventario (recepción/ajuste/conteo). **Captura de foto** en el editor de producto (tomar con
      cámara o galería vía `image_picker`, miniatura + quitar; permiso CAMERA en el manifest, no
      obligatorio). **Rediseño responsivo de venta** (`sale_screen.dart` con `LayoutBuilder`): tablet
      ancha = dos paneles (carrito 40% + vitrina 60%); cel/angosto = vitrina full + barra de carrito
      inferior con bottom sheet. Vitrina = `GridView.builder` de mosaicos con foto (miniatura en
      memoria vía `ResizeImage`), pestañas de categoría, botón de cámara. **Catálogo de prueba**
      (`lib/data/demo_seed.dart` + Admin→"Cargar catálogo de prueba"): 100 productos con variantes
      talla×color, stock e imágenes (24 fotos libres reutilizadas en `assets/demo/`, ~788 KB;
      genéricas para demo, el dueño pone las reales con la captura). **Optimización**: rejilla
      perezosa, miniaturas en memoria, índices `idx_products_category`/`idx_products_name`, búsqueda
      con debounce 250 ms. 67 pruebas verdes (7 nuevas: migración v5, ImageService ×4, demo seed ×2),
      analyze limpio. Dispositivo objetivo: Xiaomi Poco X7. **Pendiente hardware** (sin cambio):
      ESC/POS térmico, ZPL físico. Las fotos del demo son de relleno; el dueño las reemplaza.

- [x] **Fase 13 — Restauración segura del respaldo**. Cerrada 2026-07-26 (con APK). Previene la
      pérdida de datos al cambiar de tablet. `CloudBackupService`: bandera `backup_claimed` en
      `app_settings`; **guardia** — `backupNow` NO sube si la tablet no está reclamada (una tablet
      nueva/vacía ya no puede sobrescribir el respaldo bueno de la nube). `autoClaimIfHasData` (en
      `main`, antes de `startPeriodic`) reclama solo si la base ya tiene ventas → installs existentes
      siguen respaldando sin fricción; una tablet nueva queda sin reclamar hasta que el usuario
      decida. `markClaimed` explícito. **Historial versionado**: además de `boutique.sqlite` (latest),
      copias con fecha en `history/` espaciadas (cada 6 h, poda a 10) — best-effort, nunca rompe el
      respaldo principal. UI Admin→Respaldo: aviso de "tablet nueva", botón "Empezar a respaldar esta
      tablet"; "Respaldar ahora" solo cuando está reclamada; restaurar ya trae la bandera. 72 pruebas
      verdes (5 nuevas de claim/guardia). **Pendiente/diferido:** el "login de negocio" (Supabase Auth)
      quedó fuera — en single-tenant la guardia cubre el riesgo sin login; se retoma si se hace
      multi-tienda (requiere que el dueño active email auth en Supabase). Sigue pendiente del dueño el
      SQL de Supabase de la Fase 8 para que el respaldo en la nube opere en el dispositivo.

- [x] **Fase 14 — Clientes (CRM ligero)**. Cerrada 2026-07-26 (con APK). **Sin cambio de esquema**:
      usa `customers` y `sales.customerId` que ya existían (checkout ya aceptaba `customerId`).
      `CustomerRepository`: crear/editar/buscar (nombre o teléfono), `history` (ventas del cliente),
      `stats` (compras, gasto de por vida, última visita; cuenta estados completed/returned/
      partialReturn). UI `lib/features/customers/`: `CustomersScreen` (lista con búsqueda + alta),
      `CustomerDetailScreen` (datos + tarjetas de totales + historial), editor (alta/edición) y
      `pickCustomer` (selector para la venta: buscar/elegir/crear al vuelo). En `sale_screen`: botón
      de cliente en la barra + chip visible + se pasa `customerId` al cobro y se limpia tras la venta.
      Enlazado en Admin→Clientes. 77 pruebas verdes (5 nuevas de clientes). Base para lealtad/gift
      cards (Fases 15-16).

- [x] **Fase 15 — Lealtad (puntos)**. Cerrada 2026-07-26 (con APK). Una sesión previa la dejó a
      medias (se quedó sin uso): `sale_screen` usaba `availablePoints`/`redeemPoints` que el
      `_PaymentSheet` no definía → **el proyecto NO compilaba**; se completó. `LoyaltyRepository`
      sobre ledger append-only `loyalty_transactions` (earn/redeem/adjust): `balance`, `history`,
      `config` (reglas en `app_settings`: `loyalty_earn_per_peso` default 1, `loyalty_redeem_cents_per_point`
      default 10), `setConfig`, `adjust`. `checkout` **gana** puntos (net×earnPerPeso/100) y **canjea**
      (`redeemPoints` como descuento extra = pts×redeemCentsPerPoint; valida saldo y exige cliente);
      `CheckoutResult` trae `earnedPoints`/`redeemedPoints`. UI: `_PaymentSheet` permite **elegir/cambiar
      cliente en el cobro** (arreglo pedido) y **canjear puntos** (botón máx/quitar); Admin→**Programa de
      puntos** (`loyalty_config_screen`) edita reglas; ficha de cliente muestra saldo/valor/historial y
      **ajuste manual** (regalo/corrección, gerente/admin). **Fix aparte:** la vitrina de venta recarga al
      volver a la pestaña Vender (`GlobalKey<SaleScreenState>` + `reloadCatalog`), sin perder el carrito →
      ya no hay que reiniciar tras "Cargar catálogo de prueba". 83 pruebas verdes (6 nuevas de lealtad).
      Base para gift cards (Fase 16). Sin cambio de esquema (las tablas de lealtad ya existían).

- [x] **Fase 16 — Tarjetas de regalo (gift cards)**. Cerrada 2026-07-26 (con APK). Esquema **v7**
      (migración aditiva v6→v7): tablas `gift_cards` (código único generado por la app, `GR`+12 díg.)
      y ledger append-only `gift_card_transactions` (issue/redeem/adjust, monto con signo). Enum
      `GiftCardTxType` + `PaymentMethod.giftCard`. `GiftCardRepository`: `issue` (no abre transacción
      propia, participa en la del que llama), `balance`, `findByCode`, `history`, `redeem` (valida
      saldo), `adjust`. `SalesRepository.sellGiftCard`: emite la tarjeta **y** crea una venta sin
      líneas con el pago → el dinero entra al **corte de caja** (folio + ticket). `checkout` acepta
      `PaymentInput(giftCard, monto, giftCardId)` y **debita** la tarjeta en la misma transacción
      (rollback si falta saldo). UI `lib/features/sales/gift_cards_screen.dart` (vender + consultar
      saldo/historial), enlazada en la barra de Venta; en el `_PaymentSheet` botón **"Pagar con
      tarjeta de regalo"** (teclea código → aplica saldo). Corte de caja clasifica giftCard como
      "otros" (no efectivo del cajón). 90 pruebas verdes (7 nuevas: gift card ×6 + migración v7).
      **Nota contable:** por simplicidad la emisión cuenta como venta del periodo; el canje es pago
      no-efectivo (aceptable para boutique v1). Siguiente base: lealtad+gift cards ya cubren fidelización.

## Backlog resuelto (2026-07-26, post-fases, en `main`)
Cuatro pendientes acumulados, cada uno con tests y commit propio. 60 pruebas verdes.
- **Gestión de usuarios** (`UserRepository` + Admin→Usuarios): crear cajeros/gerentes con PIN
  (4-6 díg., `mustChangePin`, sin PIN duplicado), activar/desactivar (no al último admin ni a
  sí mismo), reset de PIN. Solo admin, auditado. Desbloquea probar roles reales.
- **Descuento por línea** (Fase 5): `CheckoutLine.lineDiscountCents` se aplica antes del reparto
  del descuento por venta; botón en el carrito con autorización de gerente sobre 15%.
- **Importación CSV/Excel** (Fase 3, hueco #12): `ImportRepository` pega CSV/TSV (Excel),
  crea categorías/productos/variantes con costo, stock inicial `receipt`, código proveedor o
  interno MB; idempotente por SKU. Pantalla Catálogo→Importar con revisión previa.
- **Reconciliación** (Fase 8): `ReconciliationRepository` + Admin→Reconciliación: stock negativo,
  sobre-reservado, pagos que no cuadran (folios duplicados no aplica: `folio` es UNIQUE).

## Mejoras post-Fase 16 (2026-07-26, en `main`, sin cambio de esquema)
Todo con tests/analyze verdes (94 pruebas) y APK.
- **Reportes ampliados** (`ReportsRepository` + `reports_screen`): **Menos vendidos**
  (`variantSales(ascending: true)`), y **Recomendaciones** accionables
  (`recommendations()`: reglas sobre ventas de 30 días + existencia → Reabastecer si vende ≥3 y
  queda poco; Poner en oferta si tiene stock y sin venta 45+ días/nunca; Considerar descuento si
  sobre-stock ≥10 con venta lenta). 4 tests nuevos.
- **Rediseño de UI "premium"** (a pedido del dueño): `lib/core/theme.dart` reescrito — base blanca,
  tarjetas con borde gris + drop shadow, inputs blancos, **botones morados** de alto contraste,
  diálogos/menús/bottomSheets/popups redondeados con sombra. Estiliza TODA la app.
- **Componente reutilizable** `lib/core/dashboard_tile.dart` (`DashboardTile` + `DashboardGrid`,
  a prueba de overflow con `Flexible`): Admin, Inventario y Reportes ahora son **paneles en rejilla**.
- **Filtros**: Catálogo (buscador + chips de categoría, y **rejilla con fotos** vía
  `productImageProvider`); Usuarios (buscador + chips por rol, avatar/chips de color por rol/estado).
  Clientes y Usuarios con filas en tarjetas. La pantalla de **Vender NO se tocó** (ya gustaba).

## Orden mínimo para operar
Fases 1 → 2 → 3 → 4 → 5 dan una tienda vendiendo con corte de caja. La 6 y 7 se piden la
primera semana. La 8 (respaldo robusto) es la red de seguridad.

## Documentos
- `docs/decisiones.md` — las decisiones de Fase 0 con su justificación y los TBD.
- `docs/plan-fases.md` — el plan de construcción por fases, adaptado a Flutter.
- `docs/supabase-setup.md` — cómo dejar listo el respaldo en la nube (Fase 8).
- `docs/produccion.md` — Fase 11: firma release, monitoreo, respaldo, contingencia, checklist.
- `docs/aviso-privacidad.md` — aviso LFPDPPP simplificado para el mostrador.
- `docs/guia-rapida.md` — guía de una página para la caja.

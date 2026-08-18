# Shelby Caps — CLAUDE.md

Memoria del proyecto entre sesiones. **Actualizar al cerrar cada fase.**

## Aislamiento (no negociable)
Este proyecto es un **fork independiente del POS Boutique**, separado el 11 ago 2026.

- Repo propio: `faridzeq89/shelby-caps`. **Nunca** hacer push a `faridzeq89/POS-Boutique`
  ni traer commits de allá; ese repo atiende a otro cliente y ya está en producción.
- `applicationId` propio: **`com.shelbycaps.pos`** (el del POS Boutique es
  `com.boutique.pos_boutique`). Así ambas apps conviven en la misma tablet sin
  reemplazarse ni compartir base de datos. No volver a igualarlos.
- Proyecto de Supabase propio: **`shelbys`**. No apuntar al de la boutique.
- El paquete Dart sigue llamándose `pos_boutique` a propósito: renombrarlo obligaría a
  reescribir todos los imports sin ganar nada. La identidad la dan applicationId y marca.
- Origen: rama `feat/pos-nuevo-cliente` de POS-Boutique, 13 commits (hasta `35e00e0`).

## Qué es
Punto de venta para **Shelby Caps** (gorras), en tablet Android y también en PC
(Windows). Venta directa por mostrador con escaneo de código de barras, variantes,
inventario por SKU, apartados, devoluciones/cambios, corte de caja, **mayoreo por
cantidad**, gastos, cotizaciones, proveedores, **servicios** (precio a definir en la
cotización) y **catálogo público web** con anuncios administrables, publicado a Supabase.
Hereda del POS Boutique toda la base de retail.

## Stack (decidido)
- **Flutter** (app Android nativa) + **Drift/SQLite local** como fuente de verdad.
- **Local-first**: la tablet opera sin internet; la nube es respaldo, no dependencia.
- **Supabase** como respaldo/sincronización en la nube (dos proyectos: `dev` y `prod`).
- Impresión de ticket **ESC/POS** reutilizando lo probado en el POS Maraco (restaurante).
- Autenticación **por PIN + roles** (admin / manager / cashier). Email/password solo admin
  para el login de respaldo en la nube. El PIN al arrancar se puede saltar con el
  **acceso directo** (Ajustes → Acceso); el login sigue existiendo, ver abajo.
- Proyecto Flutter: package `pos_boutique`, applicationId **`com.boutique.pos_boutique`**,
  solo plataforma Android. Estado con `provider`, base local con `drift`.

> Nota de arquitectura vs. el documento original: el doc apuntaba a React PWA + Supabase
> (verdad en la nube, offline como fase difícil al final). Aquí es al revés: Flutter es
> offline por diseño, la Fase 8 es "sincronización a la nube", y la seguridad la impone
> la app (roles/PIN), no la RLS de Postgres (esa solo protege el espejo de respaldo).

## Sistema visual (no negociable)
De fábrica es **vino casi rojo sobre gris casi negro**, pero el color **lo elige el
dueño** desde Ajustes → Colores. Vive en cuatro archivos y en ningún otro lado:

- `core/palette.dart` — deriva la paleta completa de **un solo color** (`Palette.fromSeed`)
  midiendo contraste WCAG. El dueño solo escoge la semilla y si el fondo es oscuro o
  claro; todo lo demás se calcula para que siga leyéndose. Aquí no se ponen colores "a
  ojo": si un tono no cumple, `readableOn` lo aclara u oscurece conservando el matiz, y
  el semáforo (`success`/`danger`) se elige del que **no** se confunda con la marca.
- `core/theme.dart` — estiliza los componentes Material estándar (AppBar, Card,
  botones, inputs, diálogos). **No pongas `border:` propio en un `InputDecoration`**:
  pisa el redondeo del tema y devuelve las esquinas cuadradas de Material.
- `core/ui_kit.dart` — lo que Material no da: `AppColors`, `AppRadii`, `money()`,
  `SurfaceCard`, `SectionHeader`, `StatusPill`, `StatBlock`/`StatCard`,
  `QuickTile`, `SearchField`, `FilterChipsRow`, `EmptyState`, `AppBarTitle`.
- `services/palette_settings.dart` — guarda **solo** la semilla y oscuro/claro
  (`theme_seed`, `theme_dark`) y aplica la paleta. Nunca se guarda la paleta completa:
  así no puede quedar grabada una combinación ilegible de una versión vieja.

Reglas: ninguna pantalla define colores, radios ni formatea dinero a mano. Si algo
no se puede armar con los primitivos, **se agrega al kit**, no se copia en la
pantalla. Las listas vacías usan `EmptyState`, nunca `Center(child: Text(...))`.

**`AppColors` es mutable** (cambia al elegir color), así que sus valores **no son
`const`**: `const Icon(..., color: AppColors.accent)` no compila. Se escribe sin `const`.
`test/paleta_test.dart` mide el contraste de las 12 sugerencias **y de casos extremos**
(blanco, negro, neón, gris) en oscuro y en claro; si una pieza deja de leerse, falla.

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

## Rediseño de acceso + marca (2026-07-26, en `main`)
- **Nombre real del negocio: "Montana Boutique"** — consistente en toda la app: título de la
  app (`app.dart`), label de Android, pantalla de login, **tickets** (`ticket_service.dart`) y
  **comprobante de apartado** (`layaway_receipt.dart`). Ya no queda ningún "POS Boutique".
- **Ícono de la app**: `assets/icono-app.png` + adaptativo (`icono-foreground.png`, fondo
  `#7a1f5c`) vía `flutter_launcher_icons` (regenerar con `dart run flutter_launcher_icons`).
- **Pantalla de acceso rediseñada** (`pin_login_screen.dart`): logo con esquinas redondeadas +
  sombra, nombre de marca.
- **Teclado PIN** (`pin_pad.dart`): responde al TOCAR (onTapDown, no pierde toques rápidos) con
  **vibración** (HapticFeedback), puntos animados, tecla de avance resaltada, `PinPad` acepta
  `logo` opcional. Tests de Fase 1 actualizados al nuevo diseño. 94 pruebas verdes.

## Ajustes de UI/rendimiento (2026-07-26, en `main`)
- **Juzgar rendimiento SIEMPRE en APK `release`, no `debug`.** El debug corre 3-10× más lento;
  el "lag del teclado" y los tirones eran del build debug. En release todo va fluido (confirmado
  por el dueño). El release está firmado (Fase 12): `flutter build apk --release`.
- **Bug corregido:** Cancelar en "Nuevo cliente" hacía `pop(false)` sobre `showDialog<int>` →
  reventaba por tipo y no cerraba (el dueño creaba clientes al no poder salir). Ahora `pop()`.
  Regla: no pases un tipo distinto al de `showDialog<T>` en `Navigator.pop`.
- **Perf de reportes/inventario:** índice `idx_sale_lines_variant` (esquema **v8**); `recommendations`
  y `deadStock` reescritos con CTE `sales_agg` (agrega ventas por variante 1 vez, en vez de
  subconsultas correlacionadas por cada variante) + topes (80/200). `activeLayaways` sin N+1.
- **Responsivo:** barra de Venta colapsa acciones en menú "⋮" en teléfono (<600px); diálogos con
  `SingleChildScrollView` (no overflow con teclado); `AppDropdown` reutilizable (borde redondeado).
- Estas mejoras NO tienen tag de fase (son post-Fase 16); viven en `main`. 94 pruebas verdes.

## Catálogo: archivar/borrar + Admin→Impresoras + semilla vacía (2026-07-29, en `main`)
Sin cambio de esquema. `flutter analyze` limpio, **92 pruebas verdes** (bajó de 94: se
eliminaron los 2 tests del catálogo demo).
- **Archivar/borrar productos** (`CatalogRepository`): `setProductActive` (archiva/reactiva
  producto + sus variantes, auditado); `productHasSales`/`productHasMovements`/`canDeleteProduct`;
  `deleteProduct` = **borrado real SOLO si no tiene ventas ni movimientos**. Si hay historial
  lanza y se archiva (el ledger es append-only inmutable, no se puede borrar de verdad).
- **Editor de producto**: menú Archivar/Reactivar/Eliminar + distintivo **ARCHIVADO**; cuando
  no se puede borrar (tiene historial) ofrece archivar.
- **Admin→Impresoras** (`printers_screen.dart`, nueva): ancho de papel, listar/elegir impresora,
  **imprimir prueba**, switch de cajón de dinero. (Es la pantalla para probar el hardware ESC/POS
  pendiente.) Se quita el botón "Cargar catálogo de prueba" de Admin.
- **Semilla**: deja de sembrar los ~12 productos por defecto (solo crea sucursal + prefijo de
  dispositivo). Se **elimina `demo_seed.dart`** (los 100 productos demo) y su test → el catálogo
  **arranca vacío**; el dueño carga inventario real (o importa CSV/Excel).

## Personalización del ticket + Admin→Impresoras & Tickets (2026-07-29, en `main`)
Sin cambio de esquema (usa `app_settings`). `flutter analyze` limpio, **92 pruebas verdes**, APK.
- **`TicketConfig`** (en `ticket_service.dart`): título, subtítulo, leyenda final y **QR**, con
  `TicketConfig.load(db)` que lee de `app_settings` (claves `ticket_title`/`ticket_subheading`/
  `ticket_footer`/`ticket_qr`) y cae a los valores por defecto si faltan (retrocompatible). Se quitó
  `businessName` de `TicketData` (la marca ahora vive en `TicketConfig`).
- **`TicketService.buildPdf(data, {config})`**: el encabezado usa `config.title`; imprime el
  subtítulo y la leyenda final si no están vacíos; y dibuja el **QR** con `pw.BarcodeWidget`
  (`pw.Barcode.qrCode()`, sin dependencia nueva) cuando `qrData` tiene contenido.
- **Call sites** cargan la config y la pasan: venta (`sale_screen`, vía `_db`), liquidación de
  apartado y **comprobante de apartado** (`layaways_screen` → `layaway_receipt.dart` ahora recibe
  `TicketConfig`: usa título + subtítulo + QR; conserva "COMPROBANTE DE APARTADO" y "Conserve este
  comprobante" propios del documento). Ambos comprobantes de apartado (crear + reimprimir) pasan la
  config. Ya no queda "Montana Boutique" fijo en tickets ni comprobantes.
- **Admin renombrada a "Impresoras & Tickets"** (`printers_screen.dart` + tarjeta en `admin_screen`):
  nueva sección **Personalización del ticket** (4 campos, se guardan solos onChanged) + botón
  **Vista previa** que arma un ticket de ejemplo con la config actual. La prueba de impresión usa
  el título configurado.

## Opciones de hardware como dropdowns en Impresoras & Tickets (2026-07-29, en `main`)
Sin cambio de esquema (`app_settings`). `flutter analyze` limpio, **92 pruebas verdes**, APK.
Preparado para la futura integración ESC/POS por Bluetooth: la pantalla ya deja **elegir** con
dropdowns (`AppDropdown`), con default en lo recomendado pero cambiable:
- **Ancho de papel** (`printer_paper_mm`): 58 / **80 (default)**.
- **Impresora predeterminada** (`printer_name`): dropdown "Ninguna (elegir al imprimir)" + las
  detectadas por `Printing.listPrinters()` + la guardada aunque no esté conectada (helper
  `_printerItems()`; el nombre vacío se normaliza a null al cargar para no romper el dropdown).
  Botón de recargar al lado. *(La lista de dispositivos Bluetooth emparejados real llega con la
  integración ESC/POS directa; hoy lista impresoras del sistema.)*
- **Pin de apertura del cajón** (`printer_drawer_pin`): **Estándar pin 2 (default)** / Alternativo
  pin 5. Nota en UI: la Qian usa pin 2; si el cajón no abre, probar pin 5. Aplica con ESC/POS directo.
- **Nota de arquitectura**: la impresión NO está atada a un modelo. Hoy imprime PDF al sistema (sirve
  con cualquier impresora que Android reconozca); la integración ESC/POS directa servirá para
  cualquier térmica **ESC/POS + Bluetooth** (la Qian QOP-T80BL-RI es solo el modelo de prueba).

## Fix inventario: selector con lista/filtros + Ajuste no expulsa (2026-07-29, en `main`)
Sin cambio de esquema. `flutter analyze` limpio, **92 pruebas verdes**, APK.
- **`inventory_variant_picker.dart` rehecho**: ya no es solo búsqueda por nombre. Muestra por
  defecto la **lista de productos** (sin teclear), con **chips de filtro por categoría** (Todas +
  categorías), más búsqueda por nombre/SKU y escaneo (cámara/HID). Al tocar un producto se elige su
  variante (si tiene una sola, directo; si varias, selector talla×color con existencia). Usa
  `categories()`, `productsByCategory()`, `searchProducts()`, `variantsWithStock()`. Beneficia
  también a Recepción y Conteo (comparten el picker).
- **`adjust_stock_screen.dart`**: al aplicar el ajuste **ya NO hace `Navigator.pop`** (eso era lo que
  "sacaba" de Ajuste). Ahora se queda, re-consulta `stockFor` y limpia (`_delta=0`, nota) para seguir
  ajustando. El hub de inventario refresca el stock bajo al volver (su `_open` ya refresca en cada
  pop), así que no se pierde la actualización del badge.

## Config de Supabase dentro de la app (sin recompilar) (2026-07-29, en `main`)
Sin cambio de esquema (usa `app_settings`). `flutter analyze` limpio, **92 pruebas verdes**, APK.
Resuelve: un APK ya instalado puede conectarse a Supabase sin generar otro APK ni reinstalar.
- **`main.dart`**: `main()` ahora crea la `AppDatabase` **antes** de Supabase; `_initSupabase(db)` lee
  primero las llaves de `app_settings` (`supabase_url`, `supabase_anon`) y, si no hay, cae al `.env`
  empaquetado (retrocompatible). Si no hay ninguna → 100% local. Helper `_setting(db, key)`.
- **`cloud_backup_screen.dart`**: botón **"Configurar conexión (Supabase)"** siempre visible +
  pantalla `SupabaseConfigScreen` (captura URL + llave anon, valida, guarda en `app_settings`, ofrece
  "quitar conexión" para volver a local). Mensaje de estado deshabilitado actualizado.
- **Flujo**: Admin → Respaldo → Configurar conexión → pegar URL + anon → guardar → **cerrar y reabrir
  la app** (Supabase se inicializa al arrancar). Un reinicio, sin build ni reinstall. Sirve también
  para cambiar de proyecto/tienda o migrar de tablet. La llave anon es semi-pública (va en el APK de
  todos modos); vive en la base local (viaja en el respaldo).

## Tallas personalizadas + fixes de Recepción (2026-07-29, en `main`)
Sin cambio de esquema. `flutter analyze` limpio, **92 pruebas verdes**, APK.
- **Tallas propias en la matriz de variantes** (`product_editor_screen.dart`, `_MatrixDialog`): antes
  las tallas eran fijas (8 presets CH/M/G/XG/28-34, sin forma de agregar). Ahora hay campo **"Otras
  tallas (separadas por coma)"**; las finales = chips marcados + las escritas (`_allSizes()`, sin
  duplicar). Los colores ya eran libres.
- **Recepción — botón "Recibir" tapado**: el FAB flotante "Agregar variante" cubría el botón
  "Recibir" en la esquina inferior derecha (parecía que "no había botón para aplicar"). Se **quitó el
  FAB** y "Agregar variante" es ahora un botón visible bajo la referencia; "Recibir" queda libre.
- **Buscar por categoría en inventario**: `CatalogRepository.searchProductsOrCategory()` (nombre/SKU
  de producto **+ nombre de categoría**); el selector de inventario (`inventory_variant_picker`, usado
  por Recepción/Ajuste/Conteo) lo usa. Label actualizado a "producto, SKU o categoría".

## Tienda web y fotos (2026-08-11)
`web-catalogo/` calca el catálogo que el cliente ya usaba en Treinta (fondo blanco, foto
cuadrada, 2 columnas en celular, chips, orden, cuadrícula/lista). Es estático: sin build.

**Varias fotos por producto** (lo que el cliente pidió: una gorra necesita frente, perfil,
atrás y detalle):
- La **portada** sigue en `products.image_path`; la galería va en `product_images`
  (esquema v13). Por eso POS, tickets y catálogo no cambiaron: "hacer portada"
  **intercambia** las rutas, no borra.
- Al publicar, `CatalogSyncService` **sube las fotos al bucket público `catalog`** de
  Supabase (las rutas locales de la tablet no las puede leer la web) y manda las URLs.
- SQL: `supabase/migrations/0003_catalog_images.sql` (bucket, `catalog_images`,
  `catalog_products.description` y `publish_catalog` con un 5º argumento; la firma vieja
  de 4 se conserva para que un APK anterior no truene).

## Versión web (provisional, 2026-08-11)
Compila con `flutter build web --release --no-web-resources-cdn`. Es la salida
**provisional para iPhone** mientras se tramita la licencia de Apple: corre en Chrome o
Safari sin instalar nada.

Cómo se resolvió cada cosa que `dart:io` no da en el navegador:
- **Base de datos**: `open_db.dart` elige por import condicional — archivo SQLite en
  tablet/PC, **SQLite en WASM sobre IndexedDB** en el navegador. Requiere `sqlite3.wasm`
  y `drift_worker.js` en `web/` (versiones atadas a drift 2.34.3 / sqlite3 3.5.1).
- **Fotos**: `image_store.dart` — archivo en tablet, **data URL** en la misma columna en
  web. Ni el esquema ni las pantallas cambiaron: todo sigue siendo un `String`.
- **Respaldo en la nube**: **apagado en web** (`supportsFileBackup`), porque no hay
  archivo `.sqlite` que subir. La pantalla lo dice en vez de fallar a medias.

**`--no-web-resources-cdn` no es opcional**: sin esa bandera CanvasKit se descarga de
`gstatic.com` en cada arranque y el POS no abre sin internet.

**Advertencia operativa:** en web los datos viven **en ese navegador y en ese equipo**, y
sin respaldo en la nube. Borrar los datos del sitio los borra. No es sustituto de la
tablet: es una vista provisional.

## Anuncios de la tienda (2026-08-11, en `main`)
Esquema **v14**: `store_banners`. Menú → Ajustes → Anuncios: subir imagen (cámara o
galería), ordenar, prender/apagar y quitar; se publica solo con el mecanismo del catálogo.
- **Portada y banner comparten tabla** porque comparten todo lo demás (imagen, orden,
  publicación); `is_cover` distingue. Fijar portada **borra** la anterior y devuelve su
  ruta para que el llamador borre el archivo y no queden huérfanos.
- **Apagar ≠ borrar**: un banner apagado se queda en la lista para la próxima temporada.
- La tabla es `StoreBanners` y no `Banners` porque `Banner` **choca con el widget de
  Flutter**.
- SQL **`0004_catalog_banners.sql`**: `catalog_banners` con RLS de solo lectura para anon
  y `publish_catalog` con un 6º argumento; **se conservan las firmas de 5 y 4** para que
  un APK anterior siga publicando (sin anuncios) en vez de tronar.
- La tienda cae a los ejemplos de `config.js` si no hay banners o si el proyecto aún no
  tiene el SQL 0004: nunca se ve a medias. Los anuncios se piden **antes** que el catálogo.
- **Los `Timer` se congelan en web** al cambiar de pestaña, así que el debounce de 20 s
  nunca subía el banner: se publica con `publishNow()` y se muestra el resultado o el
  error concreto. Es la trampa que ya costó dos commits (`af31779`, `d49be5b`).

## Andamiaje de Mercado Pago (2026-08-11, en `main`)
Todo lo que **no** depende de las llaves, listo para enchufar. Sigue sin arrancar: falta
que el dueño dé de alta las credenciales y despliegue las funciones.
- SQL **`0005_orders.sql`**: `web_orders` + `list_orders(secret)` (lectura para el POS;
  `anon` no accede a los pedidos).
- Edge Functions: `create-preference` (crea la preferencia de Checkout Pro y el pedido
  `pending`, **recalcula el total en el servidor**) y `mp-webhook` (confirma consultando a
  MP y marca `paid`/`failed`).
- Tienda: botón "Pagar con Mercado Pago" detrás de `MP_ENABLED` en `config.js`
  (**hoy `false`** → botón oculto y los pedidos siguen por WhatsApp).

## Producto tipo servicio (2026-08-12, en `main`)
Esquema **v15**: `products.es_servicio` (migración v14→v15 idempotente). Para lo que no
tiene precio fijo (limpieza de gorra/tenis/bolsa): se cotiza, ahí se le pone precio según
el estado, y al pasar a venta cuenta en reportes y caja **sin mover inventario**.
- `checkout`: las líneas de servicio **no generan movimiento de inventario**.
- El precio es **opcional, no cero forzado**: hay servicios con tarifa fija. Solo se
  ocultan costo y existencias, que es lo único que de verdad no aplica.
- El selector de variante **se salta la validación de existencia** para servicios (exigía
  stock > 0, lo que los volvía invendibles) y muestra "Servicio — sin inventario". Si no
  trae precio, lo **pregunta al agregarlo** en vez de meter un renglón en $0.
- **`SaleHandoff`** reemplaza al `Navigator.pop(cotización)` de "Pasar a venta": eso solo
  funcionaba si Cotizaciones se abría desde Venta; desde el menú lateral o Inicio la
  cotización se perdía en silencio. Ahora quien la pase la deja ahí, el shell salta a
  Vender y Venta la recoge — el origen deja de importar. El handoff **se consume una sola
  vez** (si no, el carrito se recargaría dos veces).

## Interruptor de IVA, apagado de fábrica (2026-08-12, en `main`)
El cliente **no factura**: el precio de la etiqueta es lo que se cobra. Menú → Ajustes →
IVA. Apagado desaparece del carrito, del ticket y de los reportes, y las ventas nuevas se
guardan con impuesto **cero**.
- **El impuesto se decide al cobrar, no al pintar**: `checkout` recibe `taxEnabled` y
  desglosa con tasa 0. Ocultarlo solo en pantalla habría dejado ventas guardando un IVA
  que nadie cobró y reportes mintiendo.
- **El historial no se reescribe**: las ventas ya cobradas conservan su desglose. Un
  reporte que cruce el antes y el después mezcla ambos criterios — está avisado en la
  pantalla del ajuste y fijado con una prueba.
- La tasa sigue viviendo **en el producto**; el interruptor solo decide si se usa.
- El renglón de IVA se imprime solo si el importe es mayor a cero: una venta vieja lo
  sigue mostrando y una nueva no imprime "IVA incluido $0".
- Es interruptor y no borrado **a propósito**: el día que facture, prenderlo devuelve el
  desglose sin tocar código.

## Compartir tickets (2026-08-12, en `main`)
Antes solo se abría el diálogo de impresión del sistema; compartir estaba escondido tras
"guardar como PDF" y buscar el archivo a mano, así que **en la práctica no se le podía
mandar el ticket al cliente por WhatsApp**. Ahora al generar cualquier documento sale una
hoja con **Compartir** e **Imprimir**. Cubre los cinco puntos donde se genera PDF: venta,
cotización, alta de apartado, liquidación y reimpresión. Sin dependencia nueva
(`printing` ya traía `sharePdf`).

## La barra de abajo la arma el dueño (2026-08-12, en `main`)
Menú → Ajustes → Menú rápido: elegir botones, quitarlos y arrastrarlos. Además de las
cuatro de siempre se pueden poner Cotizar, Apartados, Devoluciones, Tarjetas, Clientes,
Gastos y Proveedores.
- **Hay dos tipos de botón.** Las *pestañas* (Inicio, Vender, Inventario, Balance) viven
  siempre en el `IndexedStack` y conservan su estado: si el dueño quita "Vender" de la
  barra, la pantalla sigue ahí **con su carrito intacto** y solo pierde el atajo. Sacarlas
  de verdad habría tirado un carrito a medio armar. Los *atajos* abren pantalla encima y
  **nunca** se marcan como seleccionados: no son un lugar donde uno "está". Hay una prueba
  que fija que las cuatro pestañas sigan siendo pestañas.
- Barra vacía no existe (vuelve a lo de fábrica); un id desconocido de una config vieja se
  ignora en silencio en vez de tumbar la pantalla; Gastos y Proveedores no aparecen para
  un cajero aunque estén guardados.
- **Se reemplaza el `NavigationBar` de Material** por una barra propia: el de Material
  exige un número fijo de destinos, siempre pinta etiquetas y obliga a un `selectedIndex`
  válido; aquí hacen falta cantidad libre, etiquetas condicionales y atajos sin selección.
- Con 5 botones el nombre se dibuja más chico (10.5 en vez de 11.5) y usa
  `FittedBox(scaleDown)`: "Devoluciones" se encoge y **se lee entero** en vez de quedar en
  "Devolucion…". **Medir con `TextPainter` en pruebas no sirve**: Flutter usa una fuente
  de relleno donde toda letra ocupa lo mismo y exagera los anchos casi al doble.

## Colores elegibles por el dueño (2026-08-12/13, en `main`)
La paleta vino sobre gris casi negro y el selector de color están descritos arriba, en
**Sistema visual**. Lo que no hay que volver a aprender: **son dos vinos**, uno de relleno
y otro aclarado para texto (el de relleno como texto sobre fondo oscuro da 2.5:1 y no se
lee); y **en oscuro las sombras no se perciben**, así que las tarjetas se separan del
fondo por luz y borde, subiendo un escalón en vez de bajarlo. La tienda web toma el vino
como acento pero **conserva el fondo claro**: un catálogo de venta se lee mejor con las
fotos sobre blanco.

## Durabilidad en web: `web/_headers` no es opcional (2026-08-17, en `main`)
El cliente reportó el 13 ago que en el POS web se le perdían cambios. **La causa no era
el código:** el sitio desplegado no mandaba las cabeceras de aislamiento, así que drift
caía a **IndexedDB**, que el propio sqlite3 documenta como *escribe sin garantías de
durabilidad* — cambias un precio, cierras la pestaña y el volcado puede no alcanzar a
ocurrir. `web/serve.json` (servidor local) **sí** traía las cabeceras desde siempre; por
eso en pruebas locales nunca se reprodujo y en producción sí.

- **`web/_headers`** (nuevo): COOP `same-origin` + COEP `require-corp` para Cloudflare
  Pages. Flutter lo copia tal cual a `build/web/`. Sin él no hay `SharedArrayBuffer`, y
  sin eso Chrome y Safari **no pueden** usar OPFS (la vía `opfsLocks` de drift usa
  `Atomics.wait`; la otra, `opfsShared`, solo existe en Firefox).
- **`open_db_web.dart`**: pide OPFS con `moveExistingIndexedDbToOpfs: true` (drift, por
  omisión, se queda en IndexedDB si ya había base ahí — justo el caso del cliente),
  pide `navigator.storage.persist()` y expone `storageKind` / `storageIsDurable` /
  `storageMissingFeatures`. `open_db_native.dart` declara las mismas para que la UI
  compartida compile en las tres superficies.
- **La app lo dice cuando no puede garantizarlo**: `core/storage_notice.dart`
  (`StorageDurabilityNotice`) sobre el primitivo nuevo `WarningBanner` del kit. Va arriba
  de Inicio y, con diagnóstico técnico, en Admin → Respaldo. Si el guardado es durable
  devuelve un widget de tamaño cero: en tablet nunca se ve.
- **Verificado en el navegador**, no solo en el código: sin cabeceras la base queda en
  IndexedDB y OPFS vacío; al agregarlas, `crossOriginIsolated` pasa a `true`, aparece
  `drift_db/boutique_pos` en OPFS (434 KB) y **IndexedDB queda vacío** — o sea, drift
  mudó la base existente, no creó una nueva. Comprobar tras cada despliegue con
  `crossOriginIsolated` en la consola.
- **Costo de las cabeceras**: la página ya no carga recursos de otros orígenes sin
  CORS/CORP. Hoy no carga ninguno (CanvasKit local, fotos en data URL, Supabase por
  fetch con CORS). Si algún día se agrega una imagen o script externo, revisar aquí.
- 207 pruebas verdes (3 nuevas en `test/storage_notice_test.dart`), analyze limpio.

## Acceso directo: entrar sin PIN (2026-08-17, en `main`)
Sin cambio de esquema (usa `app_settings`). El mostrador de Shelby Caps lo atiende **una
sola persona**, y teclear el PIN al arrancar no le protege nada: entra como admin de todos
modos, y las autorizaciones de gerente **ya se le saltan por rol**
(`_authorizeManager` sale con `true` si el que está adentro ya puede autorizar). En la
versión web pesa más, porque cada recarga de la pestaña lo vuelve a pedir.

- **No se quitó el login**, se salta al arrancar. `_RootGate` (en `app.dart`) quedó igual;
  lo que cambia es que `main()` puede llegar con la sesión ya iniciada.
- **`services/session_settings.dart`** (mismo patrón que `TaxSettings`): guarda el **id
  del perfil** en `auto_login_profile`, no un `true`, para que el día que haya un segundo
  usuario quede dicho **cuál** entra solo en vez de adivinarlo. Vacío = apagado, que es
  como sale de fábrica.
- **`profileToAutoLogin()` resuelve contra los perfiles activos**: si el usuario guardado
  se desactivó o se borró devuelve `null` y la app cae a la pantalla de PIN. Esa es la
  salida segura — nadie se queda afuera y nadie entra de más. Vive en `SessionSettings` y
  no suelto en `main()` justamente para poder probarlo.
- **`AuthController.loginAs`** entra sin verificar PIN. Es el único punto que lo permite y
  solo lo llama `main()`; ninguna pantalla de captura lo expone.
- **Ajustes → Acceso** (`features/admin/access_screen.dart`, solo admin): el interruptor,
  qué cambia, y un `WarningBanner` que dice lo que se pierde — quien tome el aparato entra
  como dueño y la única barrera que queda es el bloqueo del propio teléfono o tablet.
- **"Cerrar sesión" sigue siendo el escape** para prestarle el aparato a alguien más: lleva
  a la pantalla de PIN dentro de esa sesión. El acceso directo solo corre al arrancar.
- 212 pruebas verdes (5 nuevas en `test/acceso_directo_test.dart`), analyze limpio.

**Si algún día entra un cajero, apagar este interruptor.** Con él prendido el cajero
operaría con permisos de dueño (ve costos, edita precios, cancela ventas), que es
exactamente lo que el modelo de roles existe para evitar.
## "Nueva venta": elegir cobrar o cotizar al empezar (2026-08-17, en `main`)
Sin cambio de esquema. Pedido del cliente, que venía de otra app que pregunta el tipo
**antes** de armar nada y por eso no encontraba las cotizaciones.

**La función ya existía**: los botones "Cotización" y "Cobrar" viven al pie del carrito.
Lo que fallaba era dónde: en el diseño **ancho** (tablet) se ven los dos lado a lado, pero
en el **angosto** (teléfono, que es lo que usa el cliente) la barra de abajo solo traía
"Cobrar" y "Cotizar" quedaba dentro de la hoja del carrito. Ver "Cobrar" y nada más y
concluir que no se puede cotizar es una lectura correcta de lo que se veía.

- **`_NuevaVentaSheet`** (en `home_screen.dart`): hoja con dos opciones, Venta de
  productos y Cotización. Devuelve `true`/`false`/`null`.
- **Sale solo con el carrito vacío** (`_goVender`). "Vender" es una pestaña que conserva
  su estado: si preguntara cada vez que se vuelve a ella, estorbaría a media venta. Con
  carrito armado entra directo. Cerrar la hoja sin elegir no mueve de pantalla.
- **No lleva "Venta libre"** (registrar un ingreso sin tocar productos), que sí trae la
  app de la que viene el cliente: aquí el inventario es un libro mayor y una venta sin
  líneas dejaría el stock diciendo una cosa y la caja otra.
- **El modo solo decide cuál es el botón grande.** Los dos siguen a la vista, así que se
  puede cambiar de opinión con el carrito ya armado — ésa era la ventaja de decidir al
  final y no se sacrifica por preguntar al principio. En teléfono, donde solo cabe un
  botón, el grande es el del modo.
- **El título de la barra dice `COTIZACIÓN` o `VENTA`**: es el único indicador del modo y
  se ve en las dos superficies. El modo se apaga solo al guardar la cotización o al
  cobrar (los dos puntos donde se limpia el carrito).
- **Bug encontrado por las pruebas**: la hoja desbordaba 17 px en pantalla corta. Lleva
  `SingleChildScrollView`.
- 216 pruebas verdes (4 nuevas en `test/nueva_venta_test.dart`), analyze limpio.

Las pruebas fijan la ventana en 700×1400 (teléfono) a propósito: con la de 800×600 que
trae `flutter_test` por omisión, la vitrina queda en 75 px y el "carrito vacío" desborda.
Eso es artefacto de la prueba, no del POS.


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
- `docs/manual.html` — **manual completo con capturas** (puesta en marcha + uso de todo).
  Generado con capturas reales; publicado como Artifact para ver/compartir/imprimir.

## Estado operativo (2026-08-17)
Esquema local **v15**. Migraciones de Supabase **0001–0005**. Suite **216 pruebas**,
`flutter analyze` limpio.

**Tres superficies en vivo:** APK Android (mostrador), **POS web** `shelby-pos.pages.dev`
(provisional para el iPhone del cliente mientras sale la licencia de Apple — él paga los
$99) y la **tienda** `shelby-caps.pages.dev`.

Respaldo en la nube (Fase 8) **confirmado funcionando por el dueño** (SQL aplicado en dev y
prod; sube y restaura). App fluida en release. El catálogo **arranca vacío** (semilla sin
productos demo).

Pendientes del dueño:
- **Cargar inventario y fotos reales** (o importar CSV/Excel).
- **Credenciales de Mercado Pago** + desplegar las Edge Functions y prender `MP_ENABLED`;
  el andamiaje ya está. Cobro con **Mercado Pago Point** sigue sin arrancar.
- DSN de Sentry (opcional).

Pendientes de hardware: **probar impresora ESC/POS** (usar Admin → Impresoras & Tickets) y
etiquetadora ZPL.

Diferidos: traspasos multisucursal, login de negocio (Supabase Auth).

**Verificar tras cada despliegue del POS web:** `crossOriginIsolated` debe ser `true` en la
consola del navegador. Si es `false`, el POS web vuelve a perder datos — ver la sección de
durabilidad.

Pendiente menor sin decidir: `web/index.html` todavía dice `pos_boutique` en `<title>` y en
`apple-mobile-web-app-title`. Es lo que se ve en la pestaña antes de que cargue Flutter y el
nombre que queda si el cliente agrega el POS a su pantalla de inicio.

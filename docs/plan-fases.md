# Plan de construcción por fases (adaptado a Flutter local-first)

Basado en el documento de referencia, reescrito para **Flutter + Drift/SQLite** con la nube
como respaldo. Cada fase deja algo usable y tiene criterio de aceptación. **Una fase por sesión.**

## Modelo de datos (columna vertebral)
Idéntico al del documento, traducido a Drift. Puntos clave:
- **Catálogo:** `products` (estilo padre) → `variants` (el SKU real) → `barcodes` (muchos a
  uno; `source` = supplier|internal; `code` único). `categories` jerárquica.
- **Inventario = ledger:** `inventory_movements` append-only, `qty` con signo, `type` =
  receipt|sale|return|adjustment|reserve|release|count. Stock es consulta:
  `on_hand = SUM(qty)`, `reserved = reserve − release`, `available = on_hand − reserved`.
  Vista `variant_stock`; caché por trigger/DAO solo si hace falta rendimiento.
- **Venta:** `sales` (UUID de cliente, folio, status = completed|layaway|cancelled|returned|
  partial_return, `salesperson_id`, `rfc` nullable) + `sale_lines` (qty negativo en
  devolución, `original_sale_line_id`) + `payments` (tabla propia: cash|card|transfer|
  credit_note). Un método de pago por columna está PROHIBIDO.
- **Apartado:** venta con `status='layaway'` + `layaway_terms`. Reserva con movimientos
  `reserve`; al liquidar `release`+`sale`.
- **Devolución:** venta con líneas negativas apuntando a `original_sale_line_id`; genera
  movimientos positivos. Cambio = devolución + venta nueva en la **misma transacción**.
  `credit_notes` para saldo a favor.
- **Operación:** `customers` (mínimo: name, phone), `cash_sessions`, `profiles` (role +
  PIN), `audit_log`, `stock_counts`.

---

## Fase 1 — Fundación
App Flutter viva, con login por PIN y respaldo en la nube conectado. Sin negocio todavía.
- Proyecto Flutter + Drift + tema/layout base para **tablet horizontal** (targets grandes,
  sin scroll horizontal, fullscreen).
- Tabla `profiles` con `role` y PIN. Admin inicial con PIN por defecto al primer arranque
  (como Maraco), forzar cambio.
- Supabase `dev`/`prod` para respaldo; `.env` fuera del repo. Login del negocio al arrancar.
- **Aceptación:** un `cashier` entra con su PIN en la tablet, ve su nombre y rol, y no puede
  abrir pantallas de `admin`.

## Fase 2 — Esquema, seguridad de app y semillas
Toda la estructura de datos en migraciones Drift, con las reglas de integridad reales.
- Todas las tablas, enums, índices, foreign keys. Vista `variant_stock`.
- **Seguridad en la app:** `cashier` lee catálogo e inserta ventas/pagos/movimientos; no
  borra, no edita precios, no ve costos. DAO de `inventory_movements` **sin update ni delete**
  (ni para admin). RLS equivalente en Supabase para el espejo de respaldo.
- Folios consecutivos con prefijo de dispositivo (`T1-000123`).
- Semillas: ~40 productos de boutique con matriz talla×color, códigos, costos y precios.
- **Pruebas** de la lógica de dinero y del ledger (empieza aquí la suite).
- **Aceptación:** pruebas que verifican que un `cashier` no edita precios ni borra
  movimientos, y que `available` refleja una reserva simulada.

## Fase 3 — Catálogo (admin)
Cargar la mercancía real.
- CRUD de categorías y productos.
- **Generador de matriz de variantes:** eliges tallas y colores → crea los SKUs en lote con
  códigos internos. (Diferencia entre cargar en 2 horas o en 2 días.)
- Asignación de códigos: escanear UPC de proveedor para vincular, o generar interno.
- **Importación CSV/Excel** del inventario existente (hueco #12).
- Impresión de etiquetas por lote: **ambas rutas** — PDF de hojas adhesivas y ZPL (etiquetadora Zebra/Brother).
- Precios y costos con `audit_log` en cambios de precio.
- **Aceptación:** producto con 12 variantes, hoja de etiquetas impresa, y al escanear
  cualquiera de las 12 devuelve la variante correcta.

## Fase 4 — Venta, camino feliz (rebanada vertical)
La venta más simple, de punta a punta. Local (Flutter ya es offline).
- **Lector USB HID:** escucha global de teclado (RawKeyboard) con buffer y terminador Enter.
  Sin librería. Cámara solo como respaldo.
- Carrito: agregar por escaneo, buscar por nombre/SKU, cambiar cantidad, quitar línea.
- Totales con IVA desglosado (redondeo a nivel ticket).
- Cobro en **efectivo**, un pago, con cálculo de cambio.
- Impresión de ticket ESC/POS. Bandera de **ticket de regalo** sin precio (hueco #16).
- Al cerrar: `sale` + `sale_lines` + `payment` + movimientos `sale` en **una transacción
  Drift** local. Si falla la impresión, la venta **igual queda registrada**.
- **Aceptación:** venta de 3 piezas escaneadas, cobro efectivo, ticket impreso, stock de las
  3 variantes bajó exactamente 1.

## Fase 5 — Pagos múltiples, descuentos y corte de caja
Que la caja cuadre al cierre.
- Pagos divididos (varios `payments`, métodos distintos, validar suma).
- Descuentos por línea y por venta, con motivo y **autorización por PIN de gerente** sobre
  un umbral (hueco #11).
- `cash_sessions`: apertura con fondo, retiros parciales, cierre con conteo declarado vs
  esperado y reporte de diferencia.
- Cancelación de venta del día con `audit_log` (sin borrar la fila).
- **Aceptación:** abrir caja con $500, 5 ventas (una mitad tarjeta/mitad efectivo), cerrar
  caja, y el esperado en efectivo coincide con el cálculo manual.

## Fase 6 — Devoluciones y cambios
El mostrador resuelve sin llamar al dueño.
- Buscar venta por folio o escaneando el ticket.
- Seleccionar líneas/cantidades; validar contra lo ya devuelto.
- Reglas de Fase 0: días límite, ticket obligatorio, autorización.
- Reembolso en efectivo o **nota de crédito** con saldo y vencimiento.
- Cambio = devolución + venta nueva atómica, cobrando/acreditando diferencia.
- Movimientos `return`; opción de marcar pieza dañada (ajuste aparte, no vuelve a stock).
- **Aceptación:** cambio de blusa M por G con diferencia cobrada; inventario correcto en
  ambas; reintentar devolver la misma línea se rechaza.

## Fase 7 — Apartados
El flujo que más ingresos protege.
- Cliente mínimo (nombre + teléfono) sin fricción.
- Crear apartado: anticipo, plazo, piezas reservadas (`reserve`).
- Pantalla de apartados: por vencer, vencidos, saldo pendiente.
- Abonos (nuevos `payments` sobre la misma venta).
- Liquidar: `release` + `sale`, ticket final, status `completed`.
- Vencimiento: proceso programado que marca vencidos y libera reservas según política.
- Comprobante impreso con saldo y fecha límite.
- **Aceptación:** apartado de 2 piezas con 30% anticipo; dejan de estar `available` pero
  siguen en `on_hand`; dos abonos; liquidación con ticket que refleja los tres pagos.

## Fase 8 — Sincronización/respaldo en la nube y reconciliación
> **Reframe respecto al doc:** Flutter ya es offline. Esta fase NO agrega offline; agrega
> el respaldo robusto y la sincronización multi-tablet (como Maraco).
- **Outbox** de ventas, pagos y movimientos pendientes de subir a Supabase.
- **Idempotencia** por UUID de cliente: un reintento no duplica.
- Subida periódica y tras cada cobro; restauración en tablet nueva.
- Folios con prefijo de dispositivo (ya desde Fase 2) para no colisionar entre cajas.
- El stock **puede quedar negativo**; se reconcilia con un **reporte de inconsistencias**.
- Indicador visible: en línea / N pendientes / error de sincronía.
- **Aceptación:** con WiFi apagado, 4 ventas y una devolución; al reconectar suben una sola
  vez, folios correctos, sin duplicados. Recargar a media desconexión no pierde nada.

## Fase 9 — Inventario operativo
Que el inventario del sistema se parezca al de la tienda.
- Entradas (`receipt`) con escaneo, cantidades y costos.
- Ajustes con motivo obligatorio (merma, dañado, robo, error).
- **Conteo físico:** sesión, escanear/contar, reporte de diferencias, ajuste en lote.
- Alertas de stock bajo por variante (campana, como Maraco).
- Traspasos entre ubicaciones (si se activa multisucursal).
- **Aceptación:** conteo de una categoría con diferencia de 2 piezas, ajuste con motivo,
  ledger con el rastro completo.

## Fase 10 — Reportes
Que la dueña decida qué comprar la próxima temporada.
- Ventas día/semana/mes con comparativo.
- Por categoría/producto/variante: **qué tallas y colores se venden y cuáles no** (el
  reporte que paga el sistema en boutique).
- Margen por producto (último costo).
- Inventario muerto: sin venta en N días.
- Cortes históricos y diferencias por cajero.
- Devoluciones: tasa por producto.
- **Ventas por vendedor** (hueco #13).
- Exportación a Excel.
- **Aceptación:** top 10 vendidos y 10 sin movimiento en 60 días, cuadrando contra la suma
  de ventas del periodo.

## Fase 11 — Producción
Entregarlo y poder dormir.
- Firma de APK release; auditoría de roles con un `cashier` real.
- Respaldo: subida a Supabase + export semanal a almacenamiento propio.
- Monitoreo de errores (Sentry) y de fallas de sincronización.
- **Aviso de privacidad LFPDPPP** para datos de clientes de apartados (versión corta).
- Plan de contingencia: qué hace el mostrador si muere la tablet o la impresora.
- Capacitación y guía rápida de una página, plastificada, junto a la caja.
- **Aceptación:** simulacro de tablet muerta a media venta, resuelto sin pérdida de datos.

---

## Trampas conocidas (respetar al pie de la letra)
- `float`/`double` para dinero → **centavos enteros**.
- `stock` como columna editable → **el ledger es la verdad**.
- Bloquear venta por falta de stock → **la pieza en la mano gana**.
- Un solo método de pago por venta → rompe apartados y pagos divididos.
- Devoluciones como entidad separada → duplica lógica de totales e impuestos.
- Código de barras como columna única → proveedor + interno deben coexistir.
- Suponer que la etiquetadora habla ESC/POS → **no lo hace** (ZPL u otro).

# Decisiones de Fase 0

Cerradas 2026-07-25. Cambiarlas después cuesta migraciones sobre datos de venta reales.
`DECIDIDO` = fijo. `TBD` = falta confirmación de la dueña (no bloquea Fases 1–5).

## Del documento original (las 10)

| # | Decisión | Resolución | Estado |
|---|----------|-----------|--------|
| 1 | IVA incluido vs agregado | **Incluido 16%**, desglose hacia atrás. `tax_rate` **por producto**. Redondeo **a nivel ticket**. | DECIDIDO |
| 2 | Moneda y redondeo | **MXN**, dinero en **centavos enteros** (`*_cents INTEGER`). Nunca float. | DECIDIDO |
| 3 | Multisucursal | `location_id` desde el día uno con **una sola fila**. Agregarlo después al ledger duele; ocioso no cuesta. | DECIDIDO |
| 4 | Atributos de variante | **Columnas fijas** `size`, `color` + `attributes` (JSON en TEXT) para lo raro (material/temporada). | DECIDIDO |
| 5 | Códigos internos | Prefijo distinguible + 10 dígitos en **Code128**. Prefijo propuesto: `MB`. | TBD (confirmar prefijo) |
| 6 | Impresora de tickets | **ESC/POS reutilizando el enfoque de Maraco.** Falta modelo/conexión exacta (USB/Bluetooth/red). | TBD (modelo) |
| 7 | Impresora de etiquetas | Arrancar con **PDF de hojas adhesivas**. ZPL solo si compran Zebra/Brother (equipo distinto, no habla ESC/POS). | TBD (comprar o PDF) |
| 8 | Facturación CFDI | **Solo ticket en v1.** Campo `rfc` en la venta por si después se factura aparte. Integrar PAC es otro proyecto. | DECIDIDO |
| 9 | Política de apartado | Propuesta: **30% de anticipo**, plazo **30 días**; al vencer se **libera la reserva** y el anticipo queda como **nota de crédito** (no se pierde, no se devuelve efectivo). | TBD (confirmar con la dueña) |
| 10 | Política de devolución | Propuesta: **15 días** con ticket obligatorio; se prefiere **cambio o nota de crédito**; efectivo solo con **autorización de gerente** (PIN). Pieza dañada no vuelve a stock vendible. | TBD (confirmar con la dueña) |

## Huecos integrados (los 7 que faltaban)

| # | Decisión | Resolución | Estado |
|---|----------|-----------|--------|
| 11 | Autenticación en mostrador | **PIN por usuario + roles** (admin/manager/cashier) para cambio rápido. Email/password solo admin para respaldo en la nube. Habilita override de descuentos por PIN de gerente. | DECIDIDO |
| 12 | Importación inicial de inventario | **Importar catálogo desde CSV/Excel** en la Fase 3 (producto → matriz de variantes → costos → stock inicial como movimiento `receipt`). | DECIDIDO |
| 13 | Vendedor por venta | `salesperson_id` en `sales` desde el día uno (atribución y, a futuro, comisiones). Guardarlo cuesta cero; reconstruirlo es imposible. | DECIDIDO |
| 14 | Redondeo del IVA | **A nivel ticket** (desglosar una vez). Evita el "no cuadra por un peso" en el corte. | DECIDIDO (ver #1) |
| 15 | Concurrencia entre tablets | **Local-first**: se aceptan choques entre cajas y se **reconcilian** al sincronizar (Fase 8). El stock puede quedar negativo; la pieza en la mano gana. | DECIDIDO |
| 16 | Ticket de regalo | Contemplado desde la Fase 4 (bandera para imprimir **sin precio**, para cambios). | DECIDIDO (opcional) |
| 17 | Pruebas automatizadas | Suite desde la **Fase 2**, empezando por la lógica de dinero y del ledger. Meta: tocar Fase 7 sin romper Fase 4. | DECIDIDO |

## Ambigüedades menores cerradas
- **Zona horaria:** America/Mexico_City. "Día de operación" = lo que abarca un corte de caja.
- **Folio de devoluciones:** misma serie de folios que las ventas (más simple para reportes).
- **Costeo para margen:** **último costo** (`cost_cents` de la variante). Simple y suficiente para v1.

## Pendientes de la dueña (no bloquean Fases 1–5)
1. Prefijo de códigos internos (propuesto `MB`).
2. Modelo/conexión de la impresora de tickets.
3. ¿Se compra etiquetadora (ZPL) o arrancamos con PDF de hojas adhesivas?
4. Política de apartado (% anticipo, plazo, qué pasa al vencer).
5. Política de devolución (días, quién autoriza, efectivo o nota de crédito).

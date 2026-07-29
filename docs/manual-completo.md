# Manual completo — Montana Boutique (POS)

Manual de usuario de todas las funciones del punto de venta. Los marcadores
`📷 [FOTO-NN]` indican dónde va cada captura; al final está la **lista de
screenshots** que hay que tomar.

> **Convención de roles** usada en todo el manual:
> - **Cajero** — vende, cobra, hace corte de su turno.
> - **Gerente** — todo lo del cajero + autoriza descuentos/cancelaciones/ajustes.
> - **Admin** — todo, incluido el panel de Administración (catálogo, usuarios, respaldo…).

---

## 1. Acceso y sesión

### 1.1 Primer arranque
La primera vez, la app crea un **administrador** con **PIN 1234** y **obliga a
cambiarlo** de inmediato. El catálogo arranca **vacío** (sin productos de
ejemplo). 📷 [FOTO-01]

### 1.2 Iniciar sesión con PIN
Cada usuario entra tecleando su **PIN** (4–6 dígitos) en el teclado. El teclado
vibra al tocar y muestra el logo del negocio. 📷 [FOTO-02]

### 1.3 Cambiar PIN
Al entrar por primera vez (o tras un reset), pide **cambiar el PIN**. También se
puede cambiar cuando el sistema lo exige. 📷 [FOTO-03]

### 1.4 Cerrar sesión
Botón **Salir** en la barra inferior; pide confirmación antes de cerrar la sesión.

### 1.5 Navegación general
Barra inferior con: **Vender**, **Corte**, **Admin** (solo administradores) y
**Salir**. El carrito de venta se conserva al cambiar de pestaña. 📷 [FOTO-04]

---

## 2. Vender (punto de venta)

Pantalla principal de cobro. En **tablet ancha** se ven dos paneles (carrito +
vitrina); en **teléfono/pantalla angosta** la vitrina ocupa todo y el carrito va
en una barra inferior. 📷 [FOTO-05]

### 2.1 Agregar productos por escaneo
- **Con cámara**: botón de cámara → apunta al código → se agrega la variante
  exacta (talla/color) al carrito automáticamente. 📷 [FOTO-06]
- **Con lector (HID)**: el lector "teclea" el código en la barra de escaneo y se
  agrega solo. El campo queda enfocado para escanear el siguiente.
- Si el código no existe, avisa *"Código sin resultado"*.

### 2.2 Buscar producto
Botón **Buscar**: busca por nombre, elige el producto y su variante (talla/color)
para agregarlo. 📷 [FOTO-07]

### 2.3 Agregar desde la vitrina
La vitrina muestra los productos con foto, en mosaicos y con pestañas por
categoría. Al tocar un producto se elige la **variante** (talla/color) y se
agrega. 📷 [FOTO-08]

### 2.4 Carrito: cantidades y quitar
Cada línea permite **+ / −** para la cantidad y quitar la pieza.

### 2.5 Descuento por línea
Botón de **descuento en una línea** del carrito. Un descuento mayor al **15 %**
pide **autorización de gerente** (PIN). 📷 [FOTO-09]

### 2.6 Descuento a toda la venta
Descuento aplicado a la venta completa (se reparte proporcional entre líneas).
Arriba del **15 %** pide **PIN de gerente**.

### 2.7 Asignar un cliente a la venta
Botón de **cliente** en la barra: busca por nombre/teléfono, elige o **crea al
vuelo**. El cliente queda visible como chip y permite acumular puntos e historial.
📷 [FOTO-10]

### 2.8 Cobro
Botón de cobro → hoja de **Cobro**: 📷 [FOTO-11]
- **Efectivo** con cálculo de **cambio** y atajos de importe.
- **Pagos divididos**: combina **efectivo + tarjeta + transferencia**.
- **Pagar con tarjeta de regalo**: teclea el código y aplica el saldo.
- **Canjear puntos** del cliente (botón máximo/quitar) como descuento.
- Elegir/cambiar **cliente** desde el mismo cobro.

### 2.9 Ticket y ticket de regalo
La venta se guarda **antes** de imprimir (si falla la impresión, la venta no se
pierde). Se puede imprimir **ticket normal** o **ticket de regalo** (sin
precios). 📷 [FOTO-12]

### 2.10 Aviso de stock bajo
Campana con **contador** en la barra: muestra las variantes por debajo del punto
de reorden. 📷 [FOTO-13]

### 2.11 Accesos rápidos de la barra
Desde la barra de Vender se entra a **Inventario**, **Apartados**, **Tarjetas de
regalo** y **Devoluciones**. En teléfono se agrupan en el menú **⋮ (Más)**.
📷 [FOTO-14]

---

## 3. Devoluciones y cambios

Se abre desde la barra de Vender. 📷 [FOTO-15]

### 3.1 Buscar la venta
Se busca por **folio** y se listan las líneas devolvibles (descuenta lo ya
devuelto).

### 3.2 Devolución
- **Reembolso en efectivo** (pide autorización de gerente) **o** **nota de
  crédito**.
- **Pieza dañada**: se registra la devolución y un ajuste que la saca del stock
  vendible. 📷 [FOTO-16]

### 3.3 Cambio
Devolución + venta nueva en **una sola operación**: el crédito de lo devuelto se
aplica y se cobra/acredita la **diferencia**. 📷 [FOTO-17]

---

## 4. Apartados

Se abre desde la barra de Vender. Lista con secciones **por vencer** y
**vencido**. 📷 [FOTO-18]

### 4.1 Nuevo apartado
Cliente + piezas + **anticipo (mínimo 30 %)**. Reserva las piezas (siguen en
existencia pero no disponibles para venta). Imprime **comprobante**. 📷 [FOTO-19]

### 4.2 Abonos
Registrar pagos parciales sobre el apartado. 📷 [FOTO-20]

### 4.3 Liquidar
Al saldar el total: libera la reserva, marca la venta como completada e imprime
el **ticket final** con todos los pagos.

### 4.4 Procesar vencidos
Botón **Procesar vencidos**: libera las reservas vencidas y convierte lo pagado
en **nota de crédito**.

### 4.5 Reimprimir comprobante
Desde el detalle del apartado.

---

## 5. Tarjetas de regalo

Se abre desde la barra de Vender. 📷 [FOTO-21]

### 5.1 Vender / emitir tarjeta
Genera un **código único**; el dinero de la emisión entra al **corte de caja**
(con folio y ticket). 📷 [FOTO-22]

### 5.2 Consultar saldo e historial
Teclea el código para ver saldo y movimientos.

### 5.3 Pagar con tarjeta de regalo
En el **cobro** (ver 2.8): botón *Pagar con tarjeta de regalo* → teclea el código
→ debita el saldo.

---

## 6. Corte de caja

Pestaña **Corte** de la barra inferior. 📷 [FOTO-23]

### 6.1 Abrir caja
Se abre el turno con un **fondo** inicial.

### 6.2 Retiros y depósitos
Registrar salidas/entradas de efectivo del cajón (con motivo). 📷 [FOTO-24]

### 6.3 Resumen del turno
Muestra en vivo el efectivo esperado, las **ventas del turno** y permite
**cancelar** una venta (gerente/admin: no la borra, la marca cancelada y devuelve
stock).

### 6.4 Cerrar caja (arqueo)
Cierre con **conteo**: compara lo **esperado** contra lo **contado** y muestra la
**diferencia**. 📷 [FOTO-25]

---

## 7. Administración

Panel en rejilla, **solo para administradores**. Nueve módulos. 📷 [FOTO-26]

### 7.1 Catálogo
Buscador + filtros por categoría, con vista de **rejilla con fotos**. 📷 [FOTO-27]

- **Categorías**: crear y editar.
- **Nuevo producto**: nombre, categoría, precio (**IVA incluido**), costo, foto
  (cámara o galería, se **optimiza sola**). 📷 [FOTO-28]
- **Generador de matriz de variantes**: crea todas las combinaciones
  **talla × color** con su código interno (`MB…`) y stock inicial. 📷 [FOTO-29]
- **Código de proveedor**: vincular a una variante escaneando o tecleando; hay un
  **Probar escaneo** que dice a qué variante corresponde un código. 📷 [FOTO-30]
- **Editar precios/costos**: cambios auditados (quedan en registro).
- **Etiquetas**: generar **PDF (código de barras Code128)** y **ZPL** para
  etiquetadora. 📷 [FOTO-31]
- **Archivar / reactivar / eliminar** producto: se elimina de verdad solo si no
  tiene ventas ni movimientos; si tiene historial, se **archiva** (distintivo
  ARCHIVADO). 📷 [FOTO-32]
- **Importar CSV/Excel**: pega el contenido, revisa la vista previa y crea
  categorías/productos/variantes con costo y stock inicial. 📷 [FOTO-33]

### 7.2 Inventario
Hub con recepción, ajustes, conteo y stock bajo. 📷 [FOTO-34]

- **Recepción de mercancía**: registra entradas y, opcional, actualiza el costo.
  📷 [FOTO-35]
- **Ajuste de stock**: merma / dañado / robo / corrección; **motivo obligatorio**
  y autorización de gerente. 📷 [FOTO-36]
- **Conteo físico**: crear un conteo, capturar lo contado, ver **diferencias** y
  aplicarlas en lote (o cancelar). 📷 [FOTO-37]
- **Stock bajo**: variantes bajo su **punto de reorden** (min_stock). 📷 [FOTO-38]

> Todo el inventario funciona sobre un **libro mayor** que no se edita ni se
> borra; el stock siempre es una suma de movimientos.

### 7.3 Clientes (CRM)
Lista con búsqueda y alta. 📷 [FOTO-39]

- **Ficha del cliente**: datos, **totales** (compras, gasto de por vida, última
  visita) e **historial** de ventas. 📷 [FOTO-40]
- **Editar** datos.
- **Puntos**: saldo, valor y **ajuste manual** (regalo/corrección; gerente/admin).

### 7.4 Programa de puntos (lealtad)
Reglas del programa: **puntos que se ganan por peso** y **valor de canje por
punto**. (El canje se hace en el cobro; ver 2.8.) 📷 [FOTO-41]

### 7.5 Reportes
Selector de periodo (**Hoy / 7 / 30 / 60 / personalizado**) y tarjeta de resumen
con comparativo. 📷 [FOTO-42]

Reportes disponibles:
- **Resumen del periodo** (vs. periodo anterior).
- **Ventas por variante**: más vendidos, menos vendidos y desglose talla/color.
- **Margen por producto** (último costo).
- **Dead stock**: existencia sin venta en N días.
- **Arqueos de caja** (diferencias por cajero).
- **Tasa de devoluciones**.
- **Ventas por vendedor**.
- **Recomendaciones** accionables (reabastecer / poner en oferta / considerar
  descuento). 📷 [FOTO-43]
- **Exportar CSV** de cualquier reporte.

### 7.6 Usuarios
Solo admin. 📷 [FOTO-44]
- **Crear** cajeros/gerentes con **PIN** (obliga a cambiarlo, sin PIN duplicado).
- **Activar / desactivar** (no al último admin ni a uno mismo).
- **Reset de PIN**.

### 7.7 Respaldo (nube)
Estado del respaldo en la nube y acciones. 📷 [FOTO-45]
- **Reclamar** la tablet (una tablet nueva no puede sobrescribir el respaldo bueno
  hasta reclamarla).
- **Respaldar ahora**.
- **Restaurar desde la nube** (para migrar a una tablet nueva).

### 7.8 Reconciliación
Salud de datos: detecta **stock negativo**, **sobre-reservado** y **pagos que no
cuadran**. 📷 [FOTO-46]

### 7.9 Impresoras & Tickets
Configuración de impresión y personalización del ticket. 📷 [FOTO-47]

- **Ancho de papel** (58 / 80 mm) — dropdown.
- **Impresora predeterminada** — dropdown (Ninguna + detectadas) con botón de
  recargar.
- **Imprimir prueba**.
- **Personalización del ticket**: **título**, **subtítulo**, **leyenda final** y
  **QR** (URL/texto). Se guardan solos. Botón **Vista previa**. 📷 [FOTO-48]
- **Cajón de dinero**: interruptor *abrir al cobrar en efectivo* + **pin de
  apertura** (2 / 5) — dropdown. 📷 [FOTO-49]

---

## Lista de screenshots a entregar

Tómalas en **release** y en la **tablet** (Poco X7). Para que se vean con datos,
conviene tener el catálogo con algunos productos y una venta hecha.

| ID | Pantalla / estado a capturar |
|----|------------------------------|
| FOTO-01 | Primer arranque: aviso de cambiar el PIN 1234 |
| FOTO-02 | Pantalla de acceso con teclado PIN y logo |
| FOTO-03 | Pantalla de cambiar PIN |
| FOTO-04 | Barra inferior (Vender/Corte/Admin/Salir) |
| FOTO-05 | Pantalla Vender completa (tablet, dos paneles) |
| FOTO-06 | Escaneo con cámara (visor abierto) |
| FOTO-07 | Buscar producto (resultado + elegir variante) |
| FOTO-08 | Vitrina con fotos y pestañas de categoría |
| FOTO-09 | Descuento por línea (con aviso de autorización) |
| FOTO-10 | Selector/creación de cliente en la venta |
| FOTO-11 | Hoja de Cobro (efectivo + pagos divididos + puntos) |
| FOTO-12 | Opción de ticket normal vs. ticket de regalo |
| FOTO-13 | Campana de stock bajo con contador |
| FOTO-14 | Barra de Vender / menú ⋮ (Más) en teléfono |
| FOTO-15 | Devoluciones: búsqueda por folio |
| FOTO-16 | Devolución: reembolso/nota de crédito/pieza dañada |
| FOTO-17 | Cambio: diferencia a cobrar/acreditar |
| FOTO-18 | Lista de Apartados (por vencer / vencido) |
| FOTO-19 | Nuevo apartado (anticipo 30 %) |
| FOTO-20 | Detalle de apartado con abonos |
| FOTO-21 | Tarjetas de regalo (pantalla principal) |
| FOTO-22 | Emitir/vender tarjeta de regalo |
| FOTO-23 | Corte de caja (resumen del turno) |
| FOTO-24 | Retiro/depósito de efectivo |
| FOTO-25 | Cierre de caja: arqueo (esperado vs contado) |
| FOTO-26 | Panel de Administración (rejilla de módulos) |
| FOTO-27 | Catálogo (rejilla con fotos + filtros) |
| FOTO-28 | Editor de producto (con foto y campos) |
| FOTO-29 | Generador de matriz de variantes talla×color |
| FOTO-30 | Agregar código de proveedor / probar escaneo |
| FOTO-31 | Etiquetas PDF (código de barras) |
| FOTO-32 | Menú Archivar/Reactivar/Eliminar (distintivo ARCHIVADO) |
| FOTO-33 | Importar CSV/Excel (vista previa) |
| FOTO-34 | Inventario (hub) |
| FOTO-35 | Recepción de mercancía |
| FOTO-36 | Ajuste de stock (motivo obligatorio) |
| FOTO-37 | Conteo físico (diferencias) |
| FOTO-38 | Stock bajo (lista) |
| FOTO-39 | Clientes (lista + búsqueda) |
| FOTO-40 | Ficha de cliente (totales + historial) |
| FOTO-41 | Programa de puntos (reglas) |
| FOTO-42 | Reportes (selector de periodo + resumen) |
| FOTO-43 | Reporte de recomendaciones |
| FOTO-44 | Usuarios (lista + roles) |
| FOTO-45 | Respaldo en la nube (estado) |
| FOTO-46 | Reconciliación (salud de datos) |
| FOTO-47 | Impresoras & Tickets (arriba: impresora + papel) |
| FOTO-48 | Personalización del ticket + Vista previa |
| FOTO-49 | Cajón: interruptor + pin de apertura |

> **Cómo entregarlas**: nómbralas `foto-01.png`, `foto-02.png`, … y pásamelas.
> Yo las incrusto y genero el manual final en HTML (para ver, compartir e
> imprimir), como el manual anterior.

# Manual completo — Montana Boutique (POS)

Manual de usuario de todas las funciones del punto de venta. Los marcadores
`📷 [FOTO-NN]` indican dónde va cada captura; al final está la **lista de 25
screenshots** que hay que tomar.

> **Roles** (se usan en todo el manual):
> - **Cajero** — vende, cobra, hace corte de su turno.
> - **Gerente** — lo del cajero + autoriza descuentos/cancelaciones/ajustes.
> - **Admin** — todo, incluido el panel de Administración.

---

## 1. Acceso y sesión

### 1.1 Primer arranque
La primera vez, la app crea un **administrador** con **PIN 1234** y **obliga a
cambiarlo**. El catálogo arranca **vacío** (sin productos de ejemplo).

### 1.2 Iniciar sesión con PIN
Cada usuario entra con su **PIN** (4–6 dígitos). El teclado vibra al tocar y
muestra el logo del negocio. 📷 [FOTO-01]

### 1.3 Cambiar PIN
Al entrar por primera vez (o tras un reset) pide **cambiar el PIN**.

### 1.4 Cerrar sesión
Botón **Salir** en la barra inferior; pide confirmación.

### 1.5 Navegación general
Barra inferior: **Vender**, **Corte**, **Admin** (solo administradores) y
**Salir**. El carrito se conserva al cambiar de pestaña. 📷 [FOTO-02]

---

## 2. Vender (punto de venta)

En **tablet ancha** se ven dos paneles (carrito + vitrina); en **teléfono** la
vitrina ocupa todo y el carrito va en una barra inferior. 📷 [FOTO-03]

### 2.1 Agregar por escaneo
- **Cámara**: botón de cámara → apunta al código → se agrega la variante exacta
  (talla/color) al carrito automáticamente. 📷 [FOTO-04]
- **Lector (HID)**: el lector "teclea" el código en la barra y se agrega solo.
- Si no existe, avisa *"Código sin resultado"*.

### 2.2 Buscar producto
Botón **Buscar**: por nombre, eliges producto y su variante. 📷 [FOTO-05]

### 2.3 Agregar desde la vitrina
Vitrina con fotos, mosaicos y pestañas por categoría. Al tocar un producto se
elige la **variante** (talla/color) y se agrega.

### 2.4 Carrito
Cada línea tiene **+ / −** para la cantidad y quitar la pieza.

### 2.5 Descuentos
- **Por línea**: botón de descuento en una línea del carrito.
- **A toda la venta**: se reparte proporcional entre líneas.
- Cualquier descuento mayor al **15 %** pide **PIN de gerente**.

### 2.6 Asignar cliente
Botón de **cliente** en la barra: busca por nombre/teléfono, elige o **crea al
vuelo**. Queda como chip y permite acumular puntos e historial.

### 2.7 Cobro
Botón de cobro → hoja de **Cobro**: 📷 [FOTO-06]
- **Efectivo** con cálculo de **cambio** y atajos de importe.
- **Pagos divididos**: efectivo + tarjeta + transferencia.
- **Pagar con tarjeta de regalo** (teclea el código y aplica saldo).
- **Canjear puntos** del cliente como descuento.
- Elegir/cambiar **cliente** desde el mismo cobro.

### 2.8 Ticket y ticket de regalo
La venta se guarda **antes** de imprimir (si falla la impresión, no se pierde la
venta). Puede imprimirse **ticket normal** o **de regalo** (sin precios). El
diseño del ticket (título, subtítulo, leyenda y QR) se configura en Admin →
Impresoras & Tickets (ver §7.9).

### 2.9 Stock bajo
Campana con **contador** en la barra: variantes bajo el punto de reorden.

### 2.10 Accesos de la barra
Desde Vender se entra a **Inventario**, **Apartados**, **Tarjetas de regalo** y
**Devoluciones**. En teléfono se agrupan en el menú **⋮ (Más)**.

---

## 3. Devoluciones y cambios

Se abre desde la barra de Vender. 📷 [FOTO-07]

- **Buscar la venta** por **folio**; lista las líneas devolvibles (descuenta lo
  ya devuelto).
- **Devolución**: **reembolso en efectivo** (autorización de gerente) **o**
  **nota de crédito**. **Pieza dañada**: se registra y se saca del stock vendible.
- **Cambio**: devolución + venta nueva en una sola operación; se cobra/acredita
  la **diferencia**.

---

## 4. Apartados

Se abre desde la barra de Vender. Lista con **por vencer** y **vencido**.
📷 [FOTO-08]

- **Nuevo apartado**: cliente + piezas + **anticipo (mínimo 30 %)**. Reserva las
  piezas e imprime **comprobante** (con tu título/subtítulo/QR).
- **Abonos**: pagos parciales.
- **Liquidar**: al saldar, libera la reserva e imprime el **ticket final**.
- **Procesar vencidos**: libera reservas vencidas; lo pagado pasa a **nota de
  crédito**.
- **Reimprimir** comprobante desde el detalle.

---

## 5. Tarjetas de regalo

Se abre desde la barra de Vender. 📷 [FOTO-09]

- **Vender / emitir**: genera un **código único**; el dinero entra al **corte de
  caja** (con folio y ticket).
- **Consultar** saldo e historial por código.
- **Pagar con tarjeta de regalo**: en el cobro (§2.7).

---

## 6. Corte de caja

Pestaña **Corte** de la barra inferior. 📷 [FOTO-10]

- **Abrir caja** con un **fondo** inicial.
- **Retiros y depósitos** de efectivo (con motivo).
- **Resumen del turno** en vivo + **ventas del turno**; permite **cancelar** una
  venta (gerente/admin: la marca cancelada y devuelve stock).
- **Cerrar caja (arqueo)**: compara **esperado** vs **contado** y muestra la
  **diferencia**.

---

## 7. Administración

Panel en rejilla, **solo administradores**. Nueve módulos. 📷 [FOTO-11]

### 7.1 Catálogo
Buscador + filtros por categoría, con **rejilla con fotos**. 📷 [FOTO-12]

- **Categorías**: crear y editar.
- **Nuevo producto**: nombre, categoría, precio (**IVA incluido**), costo, foto
  (cámara o galería; **se optimiza sola**). 📷 [FOTO-13]
- **Generador de matriz de variantes**: crea todas las combinaciones
  **talla × color** con código interno (`MB…`) y stock inicial. 📷 [FOTO-14]
- **Código de proveedor**: vincular a una variante escaneando o tecleando; hay un
  **Probar escaneo**.
- **Editar precios/costos**: cambios auditados.
- **Etiquetas**: generar **PDF (código Code128)** y **ZPL**.
- **Archivar / reactivar / eliminar** producto: se borra de verdad solo si no
  tiene ventas ni movimientos; si tiene historial, se **archiva**.
- **Importar CSV/Excel**: pega el contenido, revisa la vista previa y crea
  categorías/productos/variantes con costo y stock inicial. 📷 [FOTO-15]

### 7.2 Inventario
Hub con recepción, ajustes, conteo y stock bajo. 📷 [FOTO-16]

- **Recepción de mercancía**: registra entradas y, opcional, actualiza costo.
- **Ajuste de stock**: merma / dañado / robo / corrección; **motivo obligatorio**
  y autorización. Al elegir la variante, el selector muestra la **lista de
  productos con filtros por categoría** (además de búsqueda y escaneo); al aplicar
  **te quedas en la pantalla** para seguir ajustando. 📷 [FOTO-17]
- **Conteo físico**: crear conteo, capturar lo contado, ver **diferencias** y
  aplicarlas en lote (o cancelar). 📷 [FOTO-18]
- **Stock bajo**: variantes bajo su **punto de reorden**.

> Todo el inventario funciona sobre un **libro mayor** que no se edita ni se
> borra; el stock siempre es una suma de movimientos.

### 7.3 Clientes (CRM)
Lista con búsqueda y alta. **Ficha**: datos, **totales** (compras, gasto de por
vida, última visita) e **historial**; **puntos** con **ajuste manual**.
📷 [FOTO-19]

### 7.4 Programa de puntos (lealtad)
Reglas: **puntos que se ganan por peso** y **valor de canje por punto**. (El
canje se hace en el cobro; §2.7.) 📷 [FOTO-20]

### 7.5 Reportes
Selector de periodo (**Hoy / 7 / 30 / 60 / personalizado**) y resumen con
comparativo. 📷 [FOTO-21]

Incluye: **Resumen del periodo**, **Ventas por variante** (más y menos vendidos,
desglose talla/color), **Margen por producto**, **Dead stock**, **Arqueos**,
**Tasa de devoluciones**, **Ventas por vendedor**, **Recomendaciones**
accionables, y **Exportar CSV**.

### 7.6 Usuarios
Solo admin: **crear** cajeros/gerentes con **PIN**, **activar/desactivar** (no al
último admin ni a uno mismo) y **reset de PIN**. 📷 [FOTO-22]

### 7.7 Respaldo (nube)
Estado del respaldo, **reclamar** la tablet, **respaldar ahora** y **restaurar**.
**Configurar conexión (Supabase)**: pega la **URL** y **llave anon** de tu
proyecto; al **cerrar y reabrir la app** queda conectada, **sin recompilar**.
📷 [FOTO-23]

### 7.8 Reconciliación
Salud de datos: detecta **stock negativo**, **sobre-reservado** y **pagos que no
cuadran**. (Sin foto; utilidad de mantenimiento.)

### 7.9 Impresoras & Tickets
Configuración de impresión y personalización del ticket. 📷 [FOTO-24]

- **Ancho de papel** (58 / 80 mm) — dropdown.
- **Impresora predeterminada** — dropdown (Ninguna + detectadas) con recargar.
- **Imprimir prueba**.
- **Personalización del ticket**: **título**, **subtítulo**, **leyenda final** y
  **QR**. Se guardan solos. Botón **Vista previa**. 📷 [FOTO-25]
- **Cajón de dinero**: interruptor *abrir al cobrar en efectivo* + **pin de
  apertura** (2 / 5) — dropdown.

---

## Lista de 25 screenshots a entregar

Tómalas en **release**, en la tablet (Poco X7). Para que se vean con datos, ten
el catálogo con algunos productos y una venta hecha.

| ID | Pantalla a capturar |
|----|---------------------|
| FOTO-01 | Acceso: teclado PIN con logo |
| FOTO-02 | Barra inferior (Vender/Corte/Admin/Salir) |
| FOTO-03 | Pantalla Vender completa (tablet, dos paneles) |
| FOTO-04 | Escaneo con cámara (visor abierto) |
| FOTO-05 | Buscar producto / elegir variante (talla-color) |
| FOTO-06 | Hoja de Cobro (efectivo + pagos divididos + puntos) |
| FOTO-07 | Devoluciones y cambios |
| FOTO-08 | Apartados (lista + nuevo apartado) |
| FOTO-09 | Tarjetas de regalo |
| FOTO-10 | Corte de caja (resumen + arqueo) |
| FOTO-11 | Panel de Administración (rejilla de módulos) |
| FOTO-12 | Catálogo (rejilla con fotos + filtros) |
| FOTO-13 | Editor de producto (con foto y campos) |
| FOTO-14 | Generador de matriz de variantes talla×color |
| FOTO-15 | Importar CSV/Excel (vista previa) |
| FOTO-16 | Inventario (hub) |
| FOTO-17 | Ajuste de inventario + selector con lista y filtros |
| FOTO-18 | Conteo físico (diferencias) |
| FOTO-19 | Ficha de cliente (totales + historial) |
| FOTO-20 | Programa de puntos (reglas) |
| FOTO-21 | Reportes (selector de periodo + resumen) |
| FOTO-22 | Usuarios (lista + roles) |
| FOTO-23 | Respaldo + Configurar conexión (Supabase) |
| FOTO-24 | Impresoras & Tickets (impresora, papel, pin del cajón) |
| FOTO-25 | Personalización del ticket + Vista previa |

> **Cómo entregarlas**: nómbralas `foto-01.png` … `foto-25.png` y pásamelas
> (todas o por tandas). Yo las incrusto y genero el **manual final en HTML**
> para ver/compartir/imprimir.

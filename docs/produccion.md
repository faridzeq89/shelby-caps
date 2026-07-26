# Fase 11 — Producción

Cómo pasar de "funciona en mi tablet" a "entregado y puedo dormir". Los pasos
que requieren **tus** credenciales (keystore, Sentry) están marcados con 🔑 y no
puede hacerlos Claude por ti: son secretos que solo tú debes tener.

---

## 1. 🔑 Firma del APK de release

El proyecto ya está **cableado** para firmar release: `android/app/build.gradle.kts`
lee `android/key.properties`. Si ese archivo no existe, cae a la firma debug (por
eso los builds no fallan). Falta que generes tu keystore **una sola vez** y lo
guardes bien: **si lo pierdes, no podrás actualizar la app publicada.**

### 1.1 Generar el keystore (una vez)

En una terminal, dentro de `C:\Users\Farid\Documents\boutique-pos\android`:

```bash
keytool -genkey -v -keystore boutique-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias boutique
```

Te pedirá una **contraseña** (anótala en tu gestor de contraseñas) y algunos
datos (nombre, organización). Guarda `boutique-release.jks` **fuera del repo** y
haz una copia en un lugar seguro (nube personal / USB).

### 1.2 Crear `android/key.properties`

Copia `android/key.properties.example` a `android/key.properties` y llena tus
valores reales (este archivo **no se sube a git**, ya está en `.gitignore`):

```properties
storePassword=TU_CONTRASEÑA
keyPassword=TU_CONTRASEÑA
keyAlias=boutique
storeFile=boutique-release.jks
```

`storeFile` es relativo a la carpeta `android/` (donde dejaste el `.jks`).

### 1.3 Construir el APK/AAB firmado

```bash
flutter build apk --release
```

Para subir a Google Play, genera el bundle:

```bash
flutter build appbundle --release
```

Verifica que quedó firmado con TU llave (no la debug):

```bash
keytool -printcert -jarfile build\app\outputs\flutter-apk\app-release.apk
```

Debe mostrar tu alias `boutique`, no `androiddebugkey`.

---

## 2. Versionado

La versión vive en `pubspec.yaml` (`version: 1.0.0+1`). Sube el número en cada
entrega: `1.0.1+2`, `1.1.0+3`, etc. El `+N` (versionCode) **debe** subir en cada
APK que instales/publiques, o Android rechaza la actualización.

---

## 3. 🔑 Monitoreo de errores (Sentry) — opcional pero recomendado

Para enterarte de crashes en la tablet real sin que el dueño te llame:

1. Crea cuenta gratis en https://sentry.io y un proyecto **Flutter**.
2. Copia el **DSN** que te da.
3. Agrega el paquete: `flutter pub add sentry_flutter`.
4. Envuelve el arranque en `lib/main.dart`:
   ```dart
   await SentryFlutter.init(
     (options) => options.dsn = 'TU_DSN',
     appRunner: () => runApp(BoutiquePosApp(...)),
   );
   ```
   El DSN va en `.env` (como las llaves de Supabase), no en el código.

Si no quieres nube de errores, el POS igual guarda todo local; esto es solo para
diagnóstico remoto.

---

## 4. Respaldo (red de seguridad)

- **Nube (Fase 8):** respaldo automático a Supabase Storage tras cada venta y cada
  15 min. **Requisito pendiente:** correr `supabase/migrations/0001_backups.sql`
  en dev y prod (ver `docs/supabase-setup.md`).
- **Export semanal manual:** una vez por semana, Admin → Respaldo en la nube →
  confirma que dice "Respaldo al día". Opcional: copia el archivo `boutique.sqlite`
  del bucket a tu almacenamiento propio (Drive/USB) como segunda copia.

---

## 5. Auditoría de roles antes de entregar

Con un usuario **cashier** real (créalo cuando exista la gestión de usuarios):

- [ ] Puede vender, cobrar e imprimir ticket.
- [ ] NO ve costos ni el margen en reportes sensibles.
- [ ] NO puede editar precios ni administrar catálogo.
- [ ] NO puede recibir mercancía, ajustar inventario ni correr conteos (o solo con
      PIN de gerente donde aplica).
- [ ] Reembolso en efectivo le pide PIN de gerente.
- [ ] No entra a Admin (ve "Acceso denegado").

> Nota: la **gestión de usuarios / crear cajeros** sigue pendiente (hueco conocido).
> Hoy solo existe el admin sembrado (PIN inicial 1234, se cambia al primer login).

---

## 6. Plan de contingencia (pegar junto a la caja)

**Si muere la tablet a media venta:**
1. La venta se guarda ANTES de imprimir y hay respaldo en la nube tras cada cobro.
2. Consigue otra tablet, instala el APK, entra como admin →
   Respaldo en la nube → **Restaurar** → cierra y reabre la app.
3. Sigue vendiendo. Lo perdido, como mucho, es la venta en curso sin cobrar.

**Si muere la impresora:**
1. La venta **igual se registra** aunque no imprima.
2. Vende sin ticket o comparte el PDF por otro medio; repón la impresora después.

**Si no hay internet:**
1. Todo funciona igual (local-first). El respaldo se reintenta solo al volver la red.

---

## 7. Checklist de entrega

- [ ] 🔑 Keystore generado, respaldado y `key.properties` creado.
- [ ] APK/AAB de release firmado con TU llave.
- [ ] Versión subida en `pubspec.yaml`.
- [ ] SQL de Supabase corrido en dev y prod; respaldo probado en la tablet.
- [ ] Aviso de privacidad impreso y visible (ver `docs/aviso-privacidad.md`).
- [ ] Guía rápida plastificada junto a la caja (ver `docs/guia-rapida.md`).
- [ ] Simulacro hecho: "tablet muerta a media venta", resuelto sin pérdida de datos.
- [ ] PIN de admin cambiado a uno real (no 1234).

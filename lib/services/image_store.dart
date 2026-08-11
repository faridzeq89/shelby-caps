/// Dónde vive físicamente una foto de producto, según la plataforma.
///
/// En tablet/PC es un **archivo** y `products.image_path` guarda su ruta.
/// En el navegador no hay disco, así que la foto se guarda **dentro de la misma
/// columna** como `data:image/jpeg;base64,…`. En ambos casos el resto de la app
/// solo maneja un `String`, y por eso ni el esquema ni las pantallas cambian.
library;

export 'image_store_native.dart'
    if (dart.library.js_interop) 'image_store_web.dart';

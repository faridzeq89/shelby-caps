/// Abre la base de datos según la plataforma.
///
/// En tablet/PC es un archivo SQLite (`dart:io` + `NativeDatabase`); en el
/// navegador no existe el sistema de archivos, así que Drift corre sobre
/// **SQLite compilado a WASM** y guarda en IndexedDB (`open_db_web.dart`).
///
/// La elección la hace el compilador con el import condicional: el código
/// nativo nunca llega al bundle web (por eso `dart:ffi` dejó de romperlo).
library;

export 'open_db_native.dart' if (dart.library.js_interop) 'open_db_web.dart';

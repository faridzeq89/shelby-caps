import 'package:flutter/material.dart';

import '../data/local/open_db.dart';
import 'ui_kit.dart';

/// Aviso de que el navegador **no** está guardando de forma durable.
///
/// Existe porque el POS web puede terminar sobre IndexedDB, que escribe sin
/// garantía de durabilidad: el dueño cambia un precio, cierra la pestaña y el
/// cambio se pierde (le pasó al cliente el 13 ago 2026). El arreglo de fondo
/// es servir la página aislada para que drift use OPFS — ver `web/_headers`.
///
/// Esto es la red de seguridad para cuando ese arreglo no aplica (navegador
/// viejo, cabeceras que no llegaron, modo privado): en vez de fingir que
/// guardó, la app lo dice. Si el guardado sí es durable **no ocupa espacio**:
/// devuelve un widget vacío, así que se puede dejar puesto sin condicionales
/// en las pantallas.
///
/// En tablet/PC nunca se muestra ([storageIsDurable] es `true` en el nativo).
class StorageDurabilityNotice extends StatelessWidget {
  const StorageDurabilityNotice({super.key, this.detailed = false});

  /// Agrega el diagnóstico técnico (qué almacenamiento tocó y qué le faltó al
  /// navegador). Va en Admin → Respaldo, no en Inicio: al dueño en el
  /// mostrador esa línea no le sirve de nada.
  final bool detailed;

  @override
  Widget build(BuildContext context) {
    if (storageIsDurable) return const SizedBox.shrink();

    final detalle = storageMissingFeatures.isEmpty
        ? 'Almacenamiento: $storageKind.'
        : 'Almacenamiento: $storageKind. Le falta al navegador: '
            '${storageMissingFeatures.join(', ')}.';

    // El margen va aquí y no en quien lo usa: así el call site es una línea
    // sola y no deja un hueco cuando el aviso no se muestra.
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: WarningBanner(
        title: 'Aquí los cambios se pueden perder',
        message: 'Este navegador no está guardando de forma segura. Si cierras '
            'la pestaña, lo último que registres puede no quedar guardado. '
            'Mientras tanto usa la tablet para las ventas del día.'
            '${detailed ? '\n\n$detalle' : ''}',
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ui_kit.dart';
import '../../services/catalog_sync_service.dart';

/// Ajustes → Publicación de la tienda.
///
/// La tienda en línea **no acumula: refleja**. Cada publicación reemplaza el
/// catálogo completo, así que el último equipo que publica gana. Con un solo
/// POS eso es justo lo que se quiere; con dos (el del dueño y uno de soporte)
/// basta con editar algo en el equivocado para borrarle el catálogo al otro.
///
/// Este interruptor es **de este equipo**: no viaja a la nube ni afecta a los
/// demás. Apagarlo aquí deja mudo a este POS sin tocar sus ventas ni su
/// inventario, que siguen siendo suyos.
class PublishSettingsScreen extends StatefulWidget {
  const PublishSettingsScreen({super.key});

  @override
  State<PublishSettingsScreen> createState() => _PublishSettingsScreenState();
}

class _PublishSettingsScreenState extends State<PublishSettingsScreen> {
  late final CatalogSyncService _sync = context.read<CatalogSyncService>();
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final v = await _sync.publishEnabled();
    if (mounted) setState(() => _enabled = v);
  }

  Future<void> _cambiar(bool value) async {
    setState(() => _enabled = value);
    await _sync.setPublishEnabled(value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(value
          ? 'Este equipo vuelve a publicar la tienda'
          : 'Este equipo ya no publica la tienda'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled;
    return Scaffold(
      appBar: AppBar(title: const Text('Publicación de la tienda')),
      body: enabled == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SurfaceCard(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Este equipo publica la tienda',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(enabled
                        ? 'Los cambios del catálogo se mandan solos a la tienda '
                            'en línea.'
                        : 'Este POS no manda nada a la tienda. Nadie más se '
                            'entera de lo que cambies aquí.'),
                    value: enabled,
                    onChanged: _cambiar,
                  ),
                ),
                const SizedBox(height: 20),
                const SectionHeader('Por qué existe esto'),
                const SurfaceCard(
                  child: Text(
                    'La tienda en línea no junta lo de varios equipos: muestra '
                    'la foto completa del último POS que publicó. Si dos '
                    'equipos tienen productos distintos, el que publique al '
                    'final reemplaza al otro.\n\n'
                    'Déjalo prendido en el equipo del mostrador —el que tiene '
                    'la mercancía de verdad— y apágalo en cualquier otro '
                    '(pruebas, soporte, un respaldo). Así ese equipo no puede '
                    'borrar el catálogo bueno ni queriendo.',
                  ),
                ),
                const SizedBox(height: 16),
                if (!enabled)
                  SurfaceCard(
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: AppColors.accent),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Mientras esté apagado, el botón Compartir de '
                            'Inventario copia la liga pero no actualiza la '
                            'tienda, y la Tarjeta digital tampoco se publica.',
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

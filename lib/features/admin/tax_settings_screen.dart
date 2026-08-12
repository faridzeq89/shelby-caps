import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ui_kit.dart';
import '../../services/tax_settings.dart';

/// Interruptor del IVA. Apagado de fábrica porque este negocio **no factura**:
/// el precio de la etiqueta es lo que se cobra, y punto.
class TaxSettingsScreen extends StatelessWidget {
  const TaxSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tax = context.watch<TaxSettings>();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('IVA')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: SwitchListTile(
              value: tax.enabled,
              onChanged: (v) => context.read<TaxSettings>().setEnabled(v),
              title: const Text('Desglosar IVA',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(tax.enabled
                  ? 'El ticket muestra cuánto del precio es IVA'
                  : 'Apagado: el precio es el precio, sin impuesto a la vista'),
            ),
          ),
          const SizedBox(height: 16),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Qué cambia',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text(
                  'Con el IVA apagado desaparece del carrito, del ticket '
                  'impreso y de los reportes, y las ventas nuevas se guardan '
                  'con impuesto cero.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SurfaceCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline,
                    size: 20, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Las ventas YA registradas conservan el desglose con el que '
                    'se cobraron: el historial no se reescribe. Por eso un '
                    'reporte que cruce el antes y el después mezclará ambos '
                    'criterios.',
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

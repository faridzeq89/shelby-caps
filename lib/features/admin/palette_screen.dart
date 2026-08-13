import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/palette.dart';
import '../../core/ui_kit.dart';
import '../../services/palette_settings.dart';

/// El dueño elige el color de su marca y si el fondo es oscuro o claro.
///
/// Solo elige **un** color: el resto lo calcula la app cuidando que todo se
/// siga leyendo. Así puede poner el color que quiera sin arruinar la pantalla.
class PaletteScreen extends StatefulWidget {
  const PaletteScreen({super.key});

  @override
  State<PaletteScreen> createState() => _PaletteScreenState();
}

class _PaletteScreenState extends State<PaletteScreen> {
  late final _hex = TextEditingController(
      text: PaletteSettings.toHex(context.read<PaletteSettings>().seed));
  String? _error;

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  Future<void> _applyHex() async {
    final c = PaletteSettings.parseHex(_hex.text);
    if (c == null) {
      setState(() => _error = 'Escribe un color como #A81C22');
      return;
    }
    setState(() => _error = null);
    await context.read<PaletteSettings>().setSeed(c);
  }

  Future<void> _pick(Color c) async {
    await context.read<PaletteSettings>().setSeed(c);
    if (mounted) _hex.text = PaletteSettings.toHex(c);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<PaletteSettings>();
    final p = settings.palette;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Colores'),
        actions: [
          TextButton(
            onPressed: () async {
              final settings = context.read<PaletteSettings>();
              await settings.reset();
              _hex.text = PaletteSettings.toHex(settings.seed);
            },
            child: const Text('Restaurar'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SurfaceCard(
            child: Text(
              'Elige el color de tu marca. Los demás tonos se calculan solos '
              'para que el texto siempre se lea, así que puedes probar sin '
              'miedo a dejar la app ilegible.',
            ),
          ),
          const SizedBox(height: 20),

          const SectionHeader('Fondo'),
          Row(
            children: [
              Expanded(
                child: _baseOption(
                    'Oscuro', 'Gris casi negro', true, settings.dark),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _baseOption(
                    'Claro', 'Fondo blanco', false, !settings.dark),
              ),
            ],
          ),
          const SizedBox(height: 20),

          const SectionHeader('Color de la marca'),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final s in paletteSuggestions)
                _swatch(s.name, s.color, s.color.toARGB32() == p.seed.toARGB32()),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _hex,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'O escribe el color',
                    hintText: '#A81C22',
                    errorText: _error,
                  ),
                  onSubmitted: (_) => _applyHex(),
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: FilledButton(
                    onPressed: _applyHex, child: const Text('Aplicar')),
              ),
            ],
          ),
          const SizedBox(height: 24),

          const SectionHeader('Cómo se va a ver'),
          _preview(p, theme),
        ],
      ),
    );
  }

  Widget _baseOption(String title, String subtitle, bool dark, bool selected) {
    return SurfaceCard(
      onTap: () => context.read<PaletteSettings>().setDark(dark),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
              color: selected ? AppColors.accent : Theme.of(context).hintColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: selected ? AppColors.accent : null)),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 11.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          if (selected)
            Icon(Icons.check_circle, size: 20, color: AppColors.accent),
        ],
      ),
    );
  }

  Widget _swatch(String name, Color color, bool selected) {
    return InkWell(
      onTap: () => _pick(color),
      borderRadius: BorderRadius.circular(AppRadii.small),
      child: SizedBox(
        width: 84,
        child: Column(
          children: [
            Container(
              height: 48,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(AppRadii.small),
                border: Border.all(
                  color: selected ? AppColors.ink : Colors.transparent,
                  width: 2.5,
                ),
              ),
              child: selected
                  ? Icon(Icons.check, color: Palette.inkFor(color))
                  : null,
            ),
            const SizedBox(height: 4),
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  /// Muestra la paleta aplicada a piezas reales de la app, para que el dueño
  /// decida viendo un botón de cobrar y no un cuadrito de color.
  Widget _preview(Palette p, ThemeData theme) {
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StatBlock(label: 'Total', value: money(129900), size: 26),
          const SizedBox(height: 12),
          Row(
            children: [
              const StatusPill('Mayoreo', icon: Icons.bolt),
              const SizedBox(width: 8),
              StatusPill('12 disponibles', color: p.success),
              const SizedBox(width: 8),
              StatusPill('Agotado', color: p.danger),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.point_of_sale),
            label: const Text('Cobrar'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () {}, child: const Text('Cotización')),
          const SizedBox(height: 12),
          Text('Texto secundario, como las ayudas y las fechas.',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

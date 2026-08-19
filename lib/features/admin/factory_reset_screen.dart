import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ui_kit.dart';
import '../../data/local/database.dart';
import '../../data/local/open_db.dart';

/// "Empezar de cero": borra **todos los datos de este dispositivo** (productos,
/// ventas, inventario, clientes, ajustes y PIN) y deja la app como recién
/// instalada. Es para entregar el equipo limpio al cliente sin pelear con los
/// ajustes del navegador.
///
/// - NO toca lo publicado en la tienda ni la tarjeta (eso vive en Supabase).
/// - Es irreversible: por eso pide teclear una palabra para confirmar.
/// - Solo aplica en la **versión web** (en la app instalada se limpia desde los
///   ajustes del sistema); en nativo la pantalla lo dice en vez de fallar.
class FactoryResetScreen extends StatefulWidget {
  const FactoryResetScreen({super.key});

  @override
  State<FactoryResetScreen> createState() => _FactoryResetScreenState();
}

class _FactoryResetScreenState extends State<FactoryResetScreen> {
  static const _word = 'BORRAR';
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _confirm.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  bool get _canWipe =>
      kIsWeb && !_busy && _confirm.text.trim().toUpperCase() == _word;

  Future<void> _wipe() async {
    // Se toma la base ANTES del diálogo (no usar el context tras el await).
    final db = context.read<AppDatabase>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('¿Borrar todo?'),
        content: const Text(
            'Se borrarán TODOS los datos de este dispositivo y no se pueden '
            'recuperar. La app quedará como nueva.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sí, borrar todo'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    // Se cierra la base para soltar el archivo antes de borrarlo. En web
    // `wipeLocalDatabaseAndReload` recarga la página y no regresa aquí.
    await db.close();
    await wipeLocalDatabaseAndReload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Empezar de cero')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
                      const SizedBox(width: 8),
                      Text('Esto no se puede deshacer',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Borra TODO en este dispositivo: productos, ventas, '
                    'inventario, clientes, ajustes y el PIN. La app queda como '
                    'recién instalada (pedirá el PIN de fábrica 1234).\n\n'
                    'La tienda y la tarjeta publicadas NO se tocan aquí.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (!kIsWeb)
              SurfaceCard(
                child: Text(
                  'En la app instalada (Android) esto se hace desde Ajustes del '
                  'sistema → Apps → esta app → Almacenamiento → Borrar datos. '
                  'El botón de un toque solo está en la versión web.',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              )
            else ...[
              Text('Para confirmar, escribe $_word',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              TextField(
                controller: _confirm,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(hintText: _word),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error),
                onPressed: _canWipe ? _wipe : null,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.delete_forever),
                label: Text(_busy ? 'Borrando…' : 'Borrar todo y empezar de cero'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

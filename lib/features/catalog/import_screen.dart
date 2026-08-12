import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ui_kit.dart';
import '../../data/local/database.dart';
import '../../data/repositories/import_repository.dart';
import '../../services/auth_controller.dart';

/// Importación masiva del catálogo pegando texto (CSV o copiado de Excel).
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  late final ImportRepository _repo = ImportRepository(context.read<AppDatabase>());
  final _text = TextEditingController();
  ParseResult? _parsed;
  bool _busy = false;
  String? _result;

  Profile get _actor => context.read<AuthController>().currentUser!;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _review() {
    setState(() {
      _result = null;
      _parsed = _repo.parse(_text.text);
    });
  }

  Future<void> _import() async {
    final parsed = _parsed;
    if (parsed == null || parsed.rows.isEmpty) return;
    setState(() => _busy = true);
    try {
      final db = context.read<AppDatabase>();
      final loc = await db.select(db.locations).getSingleOrNull();
      final sum = await _repo.import(_actor, parsed.rows,
          locationId: loc?.id ?? 1);
      setState(() {
        _result =
            'Importado: ${sum.productsCreated} productos nuevos, ${sum.variantsCreated} variantes, '
            '${sum.unitsReceived} piezas de stock. Omitidas (ya existían): ${sum.variantsSkipped}.';
        _parsed = null;
        _text.clear();
      });
    } catch (e) {
      setState(() => _result = 'Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _parsed;
    return Scaffold(
      appBar: AppBar(title: const Text('Importar catálogo')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Pega desde Excel (columnas separadas por tabulador) o un CSV. '
              'Primera fila = encabezados. Columnas:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 4),
            SelectableText(ImportRepository.columns,
                style: const TextStyle(
                    fontFamily: 'monospace', fontWeight: FontWeight.bold)),
            const Text(
                'Obligatorias: producto, categoria, precio. El resto opcional.',
                style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: _text,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(
                  hintText:
                      'producto\tcategoria\ttalla\tcolor\tprecio\tcosto\tstock\tcodigo\n'
                      'Blusa Flor\tBlusas\tM\tRojo\t299\t120\t5\n'
                      'Blusa Flor\tBlusas\tG\tRojo\t299\t120\t3',
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (parsed != null) _preview(parsed),
            if (_result != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_result!,
                    style: TextStyle(
                        color: _result!.startsWith('Error')
                            ? Theme.of(context).colorScheme.error
                            : AppColors.success,
                        fontWeight: FontWeight.w600)),
              ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _review,
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Revisar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (_busy || parsed == null || parsed.rows.isEmpty)
                        ? null
                        : _import,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.upload_file),
                    label: Text(parsed == null
                        ? 'Importar'
                        : 'Importar ${parsed.rows.length}'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview(ParseResult p) {
    return Container(
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${p.rows.length} filas válidas',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          if (p.errors.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('${p.errors.length} con problema:',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            for (final e in p.errors.take(5))
              Text('• $e', style: const TextStyle(fontSize: 12)),
            if (p.errors.length > 5)
              Text('… y ${p.errors.length - 5} más',
                  style: const TextStyle(fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ui_kit.dart';
import '../../data/local/database.dart';
import '../../data/repositories/reconciliation_repository.dart';

/// Muestra el reporte de reconciliación (inconsistencias de datos).
class ReconciliationScreen extends StatefulWidget {
  const ReconciliationScreen({super.key});

  @override
  State<ReconciliationScreen> createState() => _ReconciliationScreenState();
}

class _ReconciliationScreenState extends State<ReconciliationScreen> {
  late final ReconciliationRepository _repo =
      ReconciliationRepository(context.read<AppDatabase>());
  late Future<List<ReconGroup>> _future = _repo.run();

  void _reload() => setState(() => _future = _repo.run());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reconciliación'),
        actions: [
          IconButton(
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar'),
        ],
      ),
      body: FutureBuilder<List<ReconGroup>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final groups = snap.data!;
          final total = groups.fold(0, (s, g) => s + g.issues.length);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: total == 0
                    ? AppColors.success.withValues(alpha: 0.12)
                    : theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(total == 0 ? Icons.check_circle : Icons.warning_amber,
                          color: total == 0
                              ? AppColors.success
                              : theme.colorScheme.error),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          total == 0
                              ? 'Todo cuadra: sin inconsistencias.'
                              : '$total inconsistencia(s) por revisar.',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              for (final g in groups)
                Card(
                  child: ExpansionTile(
                    leading: Icon(
                      g.issues.isEmpty ? Icons.check : Icons.error_outline,
                      color: g.issues.isEmpty
                          ? AppColors.success
                          : theme.colorScheme.error,
                    ),
                    title: Text('${g.name} (${g.issues.length})'),
                    subtitle: Text(g.explanation,
                        style: theme.textTheme.bodySmall),
                    childrenPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    children: g.issues.isEmpty
                        ? [const ListTile(dense: true, title: Text('Sin problemas'))]
                        : [
                            for (final i in g.issues)
                              ListTile(
                                dense: true,
                                title: Text(i.title),
                                subtitle: Text(i.detail),
                              ),
                          ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/local/database.dart';
import '../../data/repositories/loyalty_repository.dart';

/// Admin → Programa de puntos: reglas de ganar y canjear.
class LoyaltyConfigScreen extends StatefulWidget {
  const LoyaltyConfigScreen({super.key});

  @override
  State<LoyaltyConfigScreen> createState() => _LoyaltyConfigScreenState();
}

class _LoyaltyConfigScreenState extends State<LoyaltyConfigScreen> {
  late final LoyaltyRepository _repo =
      LoyaltyRepository(context.read<AppDatabase>());
  final _earn = TextEditingController();
  final _redeem = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cfg = await _repo.config();
    if (!mounted) return;
    setState(() {
      _earn.text = cfg.earnPerPeso.toString();
      _redeem.text = cfg.redeemCentsPerPoint.toString();
      _loading = false;
    });
  }

  @override
  void dispose() {
    _earn.dispose();
    _redeem.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final earn = int.tryParse(_earn.text.trim());
    final redeem = int.tryParse(_redeem.text.trim());
    if (earn == null || redeem == null) {
      _toast('Escribe números válidos');
      return;
    }
    setState(() => _saving = true);
    try {
      await _repo.setConfig(earnPerPeso: earn, redeemCentsPerPoint: redeem);
      if (mounted) _toast('Reglas guardadas');
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final redeem = int.tryParse(_redeem.text.trim()) ?? 0;
    final ptsPerPeso = redeem > 0 ? (100 / redeem) : 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Programa de puntos')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Ganancia de puntos', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: _earn,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Puntos que gana por cada \$1 gastado',
                    helperText: 'Ej. 1 → gasta \$100, gana 100 puntos',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                Text('Canje de puntos', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: _redeem,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Centavos de descuento por punto',
                    helperText: 'Ej. 10 → cada punto vale \$0.10',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                if (redeem > 0)
                  Text(
                    'Equivale a: ${ptsPerPeso.toStringAsFixed(0)} puntos = \$1 de descuento',
                    style: theme.textTheme.bodySmall,
                  ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_outlined),
                  label: const Text('Guardar reglas'),
                ),
              ],
            ),
    );
  }
}

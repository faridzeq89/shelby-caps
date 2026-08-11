import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/local/database.dart';
import '../../data/repositories/expense_repository.dart';
import '../../services/auth_controller.dart';

/// Registro de gastos del negocio: lista reciente con total del mes y alta
/// rápida (categoría sugerida + monto + nota).
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  late final ExpenseRepository _repo =
      ExpenseRepository(context.read<AppDatabase>());
  late Future<_Data> _future = _load();

  Profile get _actor => context.read<AuthController>().currentUser!;

  Future<_Data> _load() async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final nextMonth = DateTime(now.year, now.month + 1, 1);
    final list = await _repo.recent();
    final monthTotal = await _repo.totalBetween(monthStart, nextMonth);
    return _Data(list, monthTotal);
  }

  void _reload() => setState(() => _future = _load());

  void _toast(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  String _money(int c) => '\$${(c / 100).toStringAsFixed(2)}';

  Future<void> _addExpense() async {
    final result = await showModalBottomSheet<_ExpenseInput>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ExpenseSheet(),
    );
    if (result == null) return;
    try {
      await _repo.addExpense(
        actor: _actor,
        category: result.category,
        amountCents: result.amountCents,
        note: result.note,
      );
      _toast('Gasto registrado');
      _reload();
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _delete(Expense e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Borrar gasto'),
        content: Text(
            '¿Borrar "${e.category}" por ${_money(e.amountCents)}? No se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.deleteExpense(_actor, e.id);
      _reload();
    } catch (err) {
      _toast('$err');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final df = DateFormat('dd/MM/yy HH:mm');
    return Scaffold(
      appBar: AppBar(title: const Text('Gastos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addExpense,
        icon: const Icon(Icons.add),
        label: const Text('Registrar gasto'),
      ),
      body: FutureBuilder<_Data>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data!;
          return Column(
            children: [
              Card(
                margin: const EdgeInsets.all(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Gastos de este mes',
                          style: theme.textTheme.titleMedium),
                      Text(_money(data.monthTotal),
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: data.expenses.isEmpty
                    ? const Center(
                        child: Text('Sin gastos registrados.\nToca "Registrar gasto".',
                            textAlign: TextAlign.center))
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: data.expenses.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final e = data.expenses[i];
                          return ListTile(
                            leading: const CircleAvatar(
                                child: Icon(Icons.receipt_long_outlined)),
                            title: Text(
                                '${e.category}  ·  ${_money(e.amountCents)}'),
                            subtitle: Text([
                              df.format(e.createdAt),
                              if (e.note != null && e.note!.isNotEmpty) e.note!,
                            ].join('  ·  ')),
                            trailing: IconButton(
                              tooltip: 'Borrar',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(e),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Data {
  _Data(this.expenses, this.monthTotal);
  final List<Expense> expenses;
  final int monthTotal;
}

class _ExpenseInput {
  _ExpenseInput(this.category, this.amountCents, this.note);
  final String category;
  final int amountCents;
  final String? note;
}

class _ExpenseSheet extends StatefulWidget {
  const _ExpenseSheet();

  @override
  State<_ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<_ExpenseSheet> {
  final _category = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _category.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _valid {
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    return _category.text.trim().isNotEmpty && amount > 0;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Registrar gasto',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              children: [
                for (final c in ExpenseRepository.suggestedCategories)
                  ActionChip(
                    label: Text(c),
                    onPressed: () => setState(() => _category.text = c),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _category,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  labelText: 'Categoría', hintText: 'Renta, proveedor…'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _amount,
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Monto', prefixText: '\$'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Nota (opcional)'),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _valid
                  ? () => Navigator.of(context).pop(_ExpenseInput(
                        _category.text.trim(),
                        ((double.tryParse(_amount.text.trim()) ?? 0) * 100)
                            .round(),
                        _note.text.trim().isEmpty ? null : _note.text.trim(),
                      ))
                  : null,
              icon: const Icon(Icons.check),
              label: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}

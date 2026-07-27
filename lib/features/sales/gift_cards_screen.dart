import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/local/database.dart';
import '../../data/repositories/gift_card_repository.dart';
import '../../data/repositories/sales_repository.dart';
import '../../services/auth_controller.dart';
import '../../services/cloud_backup_service.dart';

String _money(int c) => '\$${(c / 100).toStringAsFixed(2)}';

/// Tarjetas de regalo: emitir (vender) y consultar saldo.
class GiftCardsScreen extends StatefulWidget {
  const GiftCardsScreen({super.key});

  @override
  State<GiftCardsScreen> createState() => _GiftCardsScreenState();
}

class _GiftCardsScreenState extends State<GiftCardsScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final GiftCardRepository _repo = GiftCardRepository(_db);
  late final SalesRepository _sales = SalesRepository(_db);

  final _lookupCtrl = TextEditingController();
  GiftCardWithBalance? _found;
  List<GiftCardTransaction> _foundHistory = [];
  String? _lookupError;

  Profile get _cashier => context.read<AuthController>().currentUser!;

  @override
  void dispose() {
    _lookupCtrl.dispose();
    super.dispose();
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<int?> _locationId() async {
    final loc = await _db.select(_db.locations).getSingleOrNull();
    return loc?.id;
  }

  Future<void> _sell() async {
    final amount = await showDialog<int>(
      context: context,
      builder: (_) => const _AmountDialog(),
    );
    if (amount == null) return;
    final locId = await _locationId();
    if (locId == null) return;
    try {
      final res = await _sales.sellGiftCard(
        cashier: _cashier,
        locationId: locId,
        amountCents: amount,
        payments: [PaymentInput(PaymentMethod.cash, amount)],
      );
      if (mounted) context.read<CloudBackupService>().backupSoon();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Tarjeta emitida'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Saldo: ${_money(amount)}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              const Text('Código de la tarjeta:'),
              const SizedBox(height: 4),
              SelectableText(res.card.code,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1)),
              const SizedBox(height: 4),
              const Text('Anótalo en la tarjeta física o dáselo al cliente.',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: res.card.code));
                _toast('Código copiado');
              },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copiar'),
            ),
            FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Listo')),
          ],
        ),
      );
    } catch (e) {
      _toast('Error: $e');
    }
  }

  Future<void> _lookup() async {
    final code = _lookupCtrl.text.trim();
    if (code.isEmpty) return;
    final found = await _repo.findByCode(code);
    if (!mounted) return;
    if (found == null) {
      setState(() {
        _found = null;
        _foundHistory = [];
        _lookupError = 'No existe una tarjeta con ese código';
      });
      return;
    }
    final h = await _repo.history(found.card.id);
    if (!mounted) return;
    setState(() {
      _found = found;
      _foundHistory = h;
      _lookupError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final found = _found;
    return Scaffold(
      appBar: AppBar(title: const Text('Tarjetas de regalo')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _sell,
        icon: const Icon(Icons.card_giftcard),
        label: const Text('Vender tarjeta'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Consultar saldo', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _lookupCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Código de la tarjeta',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _lookup(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _lookup, child: const Text('Ver')),
            ],
          ),
          if (_lookupError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_lookupError!,
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
          if (found != null) ...[
            const SizedBox(height: 16),
            Card(
              color: theme.colorScheme.secondaryContainer,
              child: ListTile(
                leading: Icon(Icons.card_giftcard,
                    color: theme.colorScheme.onSecondaryContainer),
                title: Text('Saldo: ${_money(found.balanceCents)}',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: theme.colorScheme.onSecondaryContainer)),
                subtitle: Text(found.card.code,
                    style: TextStyle(
                        color: theme.colorScheme.onSecondaryContainer)),
              ),
            ),
            const SizedBox(height: 8),
            Text('Movimientos', style: theme.textTheme.titleMedium),
            ..._foundHistory.map((t) => ListTile(
                  dense: true,
                  leading: Icon(t.amountCents >= 0
                      ? Icons.add_circle_outline
                      : Icons.remove_circle_outline),
                  title: Text(_txLabel(t.type)),
                  subtitle: Text(
                      DateFormat('dd/MM/yyyy HH:mm').format(t.createdAt)),
                  trailing: Text(
                      '${t.amountCents >= 0 ? '+' : ''}${_money(t.amountCents)}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                )),
          ],
        ],
      ),
    );
  }

  String _txLabel(GiftCardTxType t) => switch (t) {
        GiftCardTxType.issue => 'Emisión / recarga',
        GiftCardTxType.redeem => 'Canje en venta',
        GiftCardTxType.adjust => 'Ajuste',
      };
}

/// Pide un monto en pesos y lo devuelve en centavos.
class _AmountDialog extends StatefulWidget {
  const _AmountDialog();
  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  final _ctrl = TextEditingController();
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Vender tarjeta de regalo'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
            labelText: 'Monto de la tarjeta', prefixText: '\$'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final cents =
                ((double.tryParse(_ctrl.text.trim()) ?? 0) * 100).round();
            Navigator.of(context).pop(cents > 0 ? cents : null);
          },
          child: const Text('Cobrar en efectivo'),
        ),
      ],
    );
  }
}

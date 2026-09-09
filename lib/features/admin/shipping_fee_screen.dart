import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/business_card_settings.dart';

/// Configura el **costo fijo del envío a domicilio** de la tienda en línea.
/// Se guarda en el JSON de la tarjeta (`business_card.shippingCents`) y se
/// publica con el mismo mecanismo; la tienda lo suma al total cuando el cliente
/// elige "Envío a Domicilio", y el cobro (`process-payment`) lo vuelve a sumar
/// desde este valor publicado (el cliente no puede saltárselo).
class ShippingFeeScreen extends StatefulWidget {
  const ShippingFeeScreen({super.key});

  @override
  State<ShippingFeeScreen> createState() => _ShippingFeeScreenState();
}

class _ShippingFeeScreenState extends State<ShippingFeeScreen> {
  late final BusinessCardSettings _settings =
      context.read<BusinessCardSettings>();
  final _amount = TextEditingController();
  final _freeFrom = TextEditingController();
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _settings.load();
    if (!mounted) return;
    final cents = _settings.data.shippingCents;
    final free = _settings.data.freeShippingCents;
    setState(() {
      _amount.text = cents > 0 ? (cents / 100).toStringAsFixed(0) : '';
      _freeFrom.text = free > 0 ? (free / 100).toStringAsFixed(0) : '';
      _loading = false;
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _freeFrom.dispose();
    super.dispose();
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _saveAndPublish() async {
    final pesos = double.tryParse(_amount.text.trim()) ?? 0;
    if (pesos < 0) {
      _toast('El costo no puede ser negativo');
      return;
    }
    final cents = (pesos * 100).round();
    final freePesos = double.tryParse(_freeFrom.text.trim()) ?? 0;
    final freeCents = freePesos > 0 ? (freePesos * 100).round() : 0;
    setState(() => _busy = true);
    try {
      await _settings.save(_settings.data
          .copyWith(shippingCents: cents, freeShippingCents: freeCents));
      final ok = await _settings.publish();
      if (!mounted) return;
      _toast(ok
          ? (cents > 0
              ? 'Publicado ✓ — envío \$${(cents / 100).toStringAsFixed(0)}'
              : 'Publicado ✓ — envío gratis')
          : 'Se guardó, pero no se pudo publicar: ${_settings.lastError}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Envío a domicilio')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Costo fijo que se cobra cuando el cliente elige "Envío a '
                  'Domicilio" en la tienda. Se suma al total del pedido.',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Costo de envío',
                    prefixText: '\$ ',
                    helperText: 'Déjalo vacío o en 0 para envío gratis siempre.',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _freeFrom,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Envío gratis desde',
                    prefixText: '\$ ',
                    helperText:
                        'Si el pedido llega a este monto, el envío es gratis. '
                        'Vacío o 0 = sin envío gratis.',
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _saveAndPublish,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.cloud_upload_outlined),
                    label: Text(_busy ? 'Publicando…' : 'Guardar y publicar'),
                  ),
                ),
              ],
            ),
    );
  }
}

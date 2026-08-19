import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/permissions.dart';
import '../../core/ui_kit.dart';
import '../../data/local/database.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/inventory_repository.dart';
import '../../data/repositories/supplier_repository.dart';
import '../../services/auth_controller.dart';
import '../../services/tax_settings.dart';

/// **Un solo lugar para editar el producto.**
///
/// Antes cada dato tenía su propio lápiz regado por la pantalla —nombre,
/// precio, costo, proveedor, existencias— y el dueño no sabía qué se podía
/// tocar ni dónde. Aquí se llena todo y se guarda una vez, como cualquier
/// formulario.
///
/// Solo se escribe **lo que cambió**: así el historial no se llena de ajustes
/// de cero ni de renombres que renombran a lo mismo.
///
/// Las existencias aparecen cuando el producto tiene **una sola variante**
/// (talla única, que es lo normal en gorras). Con matriz talla × color cada
/// variante lleva su propia existencia y se ajusta en su renglón: un campo
/// aquí tendría que preguntar "¿de cuál?".
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key, required this.productId});
  final int productId;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _FormData {
  _FormData(this.product, this.variante, this.stock, this.proveedores);
  final Product product;

  /// La variante única, o null si el producto tiene matriz (o ninguna).
  final Variant? variante;
  final int stock;
  final List<Supplier> proveedores;
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final CatalogRepository _repo = CatalogRepository(_db);
  late final InventoryRepository _inventory = InventoryRepository(_db);
  late final SupplierRepository _suppliers = SupplierRepository(_db);
  late final Future<_FormData> _future = _load();

  final _nombre = TextEditingController();
  final _marca = TextEditingController();
  final _descripcion = TextEditingController();
  final _precio = TextEditingController();
  final _costo = TextEditingController();
  final _existencias = TextEditingController();

  int? _proveedorId;
  AdjustmentReason _motivo = AdjustmentReason.correction;
  bool _guardando = false;

  Profile get _actor => context.read<AuthController>().currentUser!;
  bool get _puedeCatalogo => Permissions.canManageCatalog(_actor.role);
  bool get _puedePrecios => Permissions.canEditPrices(_actor.role);
  bool get _puedeCostos => Permissions.canSeeCosts(_actor.role);
  bool get _puedeStock => Permissions.canManageInventory(_actor.role);

  @override
  void dispose() {
    for (final c in [
      _nombre,
      _marca,
      _descripcion,
      _precio,
      _costo,
      _existencias,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<_FormData> _load() async {
    final producto = (await _repo.productById(widget.productId))!;
    final variantes = await _repo.variantsOf(widget.productId);
    final unica = variantes.length == 1 ? variantes.first : null;
    final stock = unica == null ? 0 : (await _db.stockFor(unica.id)).onHand;
    final proveedores = await _suppliers.all();

    _nombre.text = producto.name;
    _marca.text = producto.brand ?? '';
    _descripcion.text = producto.description ?? '';
    _precio.text = (producto.basePriceCents / 100).toStringAsFixed(2);
    _costo.text =
        unica == null ? '' : (unica.costCents / 100).toStringAsFixed(2);
    _existencias.text = unica == null ? '' : '$stock';
    _proveedorId = producto.supplierId;

    return _FormData(producto, unica, stock, proveedores);
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  int? _pesosACentavos(String raw) {
    final v = double.tryParse(raw.trim().replaceAll(',', '.'));
    return (v == null || v < 0) ? null : (v * 100).round();
  }

  /// Cuántas piezas se moverían. Sirve para mostrar el motivo solo cuando de
  /// verdad va a haber movimiento.
  int _deltaStock(_FormData d) {
    if (d.variante == null) return 0;
    final objetivo = int.tryParse(_existencias.text.trim());
    if (objetivo == null || objetivo < 0) return 0;
    return objetivo - d.stock;
  }

  Future<void> _guardar(_FormData d) async {
    final nombre = _nombre.text.trim();
    if (_puedeCatalogo && nombre.isEmpty) {
      _toast('El nombre no puede quedar vacío');
      return;
    }
    final precio = _pesosACentavos(_precio.text);
    if (_puedePrecios && precio == null) {
      _toast('El precio no es válido');
      return;
    }
    final costo = _pesosACentavos(_costo.text);
    if (_puedeCostos && d.variante != null && costo == null) {
      _toast('El costo no es válido');
      return;
    }
    final objetivo = int.tryParse(_existencias.text.trim());
    if (_puedeStock &&
        d.variante != null &&
        (objetivo == null || objetivo < 0)) {
      _toast('Las existencias tienen que ser un número de 0 en adelante');
      return;
    }

    setState(() => _guardando = true);
    final hechos = <String>[];
    try {
      if (_puedeCatalogo && nombre != d.product.name) {
        await _repo.updateProductName(
            actor: _actor, productId: d.product.id, newName: nombre);
        hechos.add('nombre');
      }

      final marca = _marca.text.trim();
      final desc = _descripcion.text.trim();
      if (_puedeCatalogo &&
          (marca != (d.product.brand ?? '') ||
              desc != (d.product.description ?? ''))) {
        await _repo.updateProductPresentation(
            actor: _actor,
            productId: d.product.id,
            brand: marca,
            description: desc);
        hechos.add('marca/descripción');
      }

      if (_puedePrecios &&
          precio != null &&
          precio != d.product.basePriceCents) {
        await _repo.updateProductBasePrice(
            actor: _actor, productId: d.product.id, newPriceCents: precio);
        hechos.add('precio');
      }

      if (_puedeCostos &&
          d.variante != null &&
          costo != null &&
          costo != d.variante!.costCents) {
        await _repo.updateVariantCost(
            actor: _actor, variantId: d.variante!.id, newCostCents: costo);
        hechos.add('costo');
      }

      if (_puedeCatalogo && _proveedorId != d.product.supplierId) {
        await _repo.updateProductSupplier(
            actor: _actor, productId: d.product.id, supplierId: _proveedorId);
        hechos.add('proveedor');
      }

      // Al final a propósito: es lo único que asienta un movimiento en el libro
      // mayor. Si algo de arriba falla, no queda un ajuste huérfano ya escrito.
      final delta = _deltaStock(d);
      if (_puedeStock && d.variante != null && delta != 0) {
        await _inventory.adjust(
          _actor,
          variantId: d.variante!.id,
          locationId: await _inventory.defaultLocationId(),
          qty: delta,
          reason: _motivo,
        );
        hechos.add('existencias');
      }

      if (!mounted) return;
      if (hechos.isEmpty) {
        setState(() => _guardando = false);
        _toast('No cambiaste nada');
        return;
      }
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        _toast('No se pudo guardar: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_FormData>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final d = snap.data!;
        final tax = context.watch<TaxSettings>();
        final delta = _deltaStock(d);
        return Scaffold(
          appBar: AppBar(title: const Text('Editar producto')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              const SectionHeader('Qué es'),
              TextField(
                controller: _nombre,
                enabled: _puedeCatalogo,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  helperText: 'Como aparece en el ticket y en la tienda',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _marca,
                enabled: _puedeCatalogo,
                textCapitalization: TextCapitalization.words,
                decoration:
                    const InputDecoration(labelText: 'Marca (opcional)'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _descripcion,
                enabled: _puedeCatalogo,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Descripción (opcional)',
                  helperText: 'Se ve en la tienda web, debajo del nombre',
                ),
              ),
              const SizedBox(height: 24),

              const SectionHeader('Cuánto cuesta'),
              TextField(
                controller: _precio,
                enabled: _puedePrecios,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Precio de venta', prefixText: '\$'),
              ),
              if (_puedeCostos && d.variante != null) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _costo,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Costo (lo que te costó)',
                    prefixText: '\$',
                    helperText: 'Solo tú lo ves; sirve para la ganancia',
                  ),
                ),
              ],
              // El IVA solo se anuncia si el negocio factura. Con el interruptor
              // apagado —que es como opera esta tienda— un "IVA: 16%" en la
              // ficha promete un impuesto que nunca se cobra.
              if (tax.enabled) ...[
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('IVA'),
                    Text('${(d.product.taxRateBps / 100).toStringAsFixed(0)}%',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),
              ],

              if (d.variante != null && !d.product.esServicio) ...[
                const SizedBox(height: 24),
                const SectionHeader('Cuántas tienes'),
                TextField(
                  controller: _existencias,
                  enabled: _puedeStock,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Existencias',
                    helperText: _puedeStock
                        ? 'Cuenta las piezas y escribe el total'
                        : 'Solo un gerente puede moverlas',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                if (delta != 0) ...[
                  const SizedBox(height: 12),
                  Text(
                    delta > 0
                        ? 'Se agregan $delta · de ${d.stock} a ${d.stock + delta}'
                        : 'Se descuentan ${-delta} · de ${d.stock} a ${d.stock + delta}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  // El motivo aparece solo cuando se va a mover inventario de
                  // verdad: queda asentado y alguien tendrá que explicar
                  // después por qué bajó.
                  Text('¿Por qué cambió?',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final r in AdjustmentReason.values)
                        ChoiceChip(
                          label: Text(r.label),
                          selected: _motivo == r,
                          onSelected: (_) => setState(() => _motivo = r),
                        ),
                    ],
                  ),
                ],
              ],

              const SizedBox(height: 24),
              const SectionHeader('Quién te lo surte'),
              _proveedorPicker(d),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _guardando ? null : () => _guardar(d),
                icon: _guardando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
                label: const Text('Guardar'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _proveedorPicker(_FormData d) {
    if (d.proveedores.isEmpty) {
      return Text(
        'No hay proveedores dados de alta. Se crean en el menú → Proveedores.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return DropdownButtonFormField<int?>(
      initialValue: _proveedorId,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Proveedor'),
      items: [
        const DropdownMenuItem<int?>(value: null, child: Text('Sin proveedor')),
        for (final s in d.proveedores)
          DropdownMenuItem<int?>(value: s.id, child: Text(s.name)),
      ],
      onChanged:
          _puedeCatalogo ? (v) => setState(() => _proveedorId = v) : null,
    );
  }
}

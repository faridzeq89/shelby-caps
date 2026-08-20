import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/ui_kit.dart';
import '../../core/app_dropdown.dart';
import '../../data/local/database.dart';
import '../../data/repositories/catalog_repository.dart';
import '../sales/ticket_service.dart';

/// Admin → Impresoras & Tickets. Configura la impresora de tickets (ancho de
/// papel), muestra las impresoras del sistema (Android / Bluetooth emparejadas)
/// para elegir una por defecto, permite una impresión de prueba, guarda si el
/// cajón de dinero debe abrirse al cobrar en efectivo, y **personaliza el
/// ticket** (título, subtítulo, leyenda final y QR) con vista previa.
///
/// Nota: la app imprime tickets como PDF al sistema (el usuario elige impresora
/// en el diálogo de Android). La impresión térmica ESC/POS DIRECTA por Bluetooth
/// y el "kick" del cajón dependen del modelo de impresora (integración aparte).
class PrintersScreen extends StatefulWidget {
  const PrintersScreen({super.key});

  @override
  State<PrintersScreen> createState() => _PrintersScreenState();
}

class _PrintersScreenState extends State<PrintersScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final CatalogRepository _catalog = CatalogRepository(_db);

  /// Resultado de la última prueba del lector, o null si no se ha probado.
  String? _scanResult;

  static const _kPaper = 'printer_paper_mm';
  static const _kDrawer = 'printer_open_drawer';
  static const _kPrinter = 'printer_name';
  static const _kDrawerPin = 'printer_drawer_pin';

  String _paper = '80';
  bool _openDrawer = false;
  String _drawerPin = '2';
  String? _printerName;
  List<Printer> _printers = const [];
  bool _scanning = false;
  bool _loaded = false;

  // Personalización del ticket.
  final _titleCtrl = TextEditingController();
  final _subheadingCtrl = TextEditingController();
  final _footerCtrl = TextEditingController();
  final _qrCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _scan();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subheadingCtrl.dispose();
    _footerCtrl.dispose();
    _qrCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<String?> _get(String key) async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> _set(String key, String value) async {
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: key, value: value),
        );
  }

  Future<void> _loadSettings() async {
    final paper = await _get(_kPaper);
    final drawer = await _get(_kDrawer);
    final printer = await _get(_kPrinter);
    final drawerPin = await _get(_kDrawerPin);
    final ticket = await TicketConfig.load(_db);
    if (!mounted) return;
    setState(() {
      _paper = paper ?? '80';
      _openDrawer = drawer == '1';
      _drawerPin = drawerPin ?? '2';
      _printerName = (printer == null || printer.isEmpty) ? null : printer;
      _titleCtrl.text = ticket.title;
      _subheadingCtrl.text = ticket.subheading;
      _footerCtrl.text = ticket.footerLegend;
      _qrCtrl.text = ticket.qrData;
      _phoneCtrl.text = ticket.businessPhone;
      _addressCtrl.text = ticket.businessAddress;
      _loaded = true;
    });
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    List<Printer> found = const [];
    try {
      found = await Printing.listPrinters();
    } catch (_) {
      found = const [];
    }
    if (!mounted) return;
    setState(() {
      _printers = found;
      _scanning = false;
    });
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _testPrint() async {
    final mm = double.tryParse(_paper) ?? 80;
    final pageWidth = mm == 58 ? 58.0 * PdfPageFormat.mm : 80.0 * PdfPageFormat.mm;
    final format = PdfPageFormat(pageWidth, double.infinity,
        marginAll: 4 * PdfPageFormat.mm);
    try {
      await Printing.layoutPdf(
        name: 'prueba_impresion',
        onLayout: (_) async {
          final doc = pw.Document();
          doc.addPage(
            pw.Page(
              pageFormat: format,
              build: (_) => pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text(_titleCtrl.text.trim().isEmpty
                      ? 'SHELBY CAPS'
                      : _titleCtrl.text.trim(),
                      style: pw.TextStyle(
                          fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 6),
                  pw.Text('Prueba de impresión'),
                  pw.SizedBox(height: 6),
                  pw.Text('Papel: $mm mm'),
                  pw.Text('Si lees esto, la impresora funciona.'),
                  pw.SizedBox(height: 10),
                  pw.Text('******************'),
                ],
              ),
            ),
          );
          return doc.save();
        },
      );
    } catch (e) {
      _toast('No se pudo imprimir: $e');
    }
  }

  /// Vista previa del ticket con la personalización actual y una venta de ejemplo.
  Future<void> _previewTicket() async {
    final cfg = TicketConfig(
      title: _titleCtrl.text.trim().isEmpty
          ? 'SHELBY CAPS'
          : _titleCtrl.text.trim(),
      subheading: _subheadingCtrl.text.trim(),
      footerLegend: _footerCtrl.text,
      qrData: _qrCtrl.text.trim(),
    );
    final sample = TicketData(
      folio: 'T1-000123',
      dateTime: DateTime.now(),
      cashierName: 'Vista previa',
      lines: const [
        TicketLine(
            description: 'Blusa manga larga (M / Negro)',
            qty: 1,
            unitPriceCents: 29900,
            lineTotalCents: 29900),
        TicketLine(
            description: 'Pantalón mezclilla (30)',
            qty: 2,
            unitPriceCents: 45000,
            lineTotalCents: 90000),
      ],
      subtotalCents: 119900,
      discountCents: 0,
      taxCents: 16538,
      totalCents: 119900,
      payments: const [('Efectivo', 120000)],
      changeCents: 100,
      gift: false,
    );
    try {
      await Printing.layoutPdf(
        name: 'vista_previa_ticket',
        onLayout: (_) => TicketService.buildPdf(sample, config: cfg),
      );
    } catch (e) {
      _toast('No se pudo generar la vista previa: $e');
    }
  }

  /// Items del dropdown de impresora: "Ninguna" (null) + las detectadas + la
  /// guardada aunque ahora no esté conectada (para no perder el valor).
  List<DropdownMenuItem<String?>> _printerItems() {
    final names = <String>{
      for (final p in _printers) p.name,
      if (_printerName != null && _printerName!.isNotEmpty) _printerName!,
    };
    return [
      const DropdownMenuItem<String?>(
        value: null,
        child: Text('Ninguna (elegir al imprimir)'),
      ),
      for (final n in names)
        DropdownMenuItem<String?>(value: n, child: Text(n)),
    ];
  }

  Future<void> _testScan(String code) async {
    if (code.trim().isEmpty) return;
    final v = await _catalog.resolveByCode(code);
    if (!mounted) return;
    setState(() {
      _scanResult = v == null
          ? 'Código "$code": sin resultado'
          : 'Código "$code" → ${v.sku}  (${v.size ?? ''} ${v.color ?? ''})';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Impresoras & Tickets')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const SectionHeader('Impresora de tickets'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppDropdown<String>(
                          label: 'Ancho de papel',
                          icon: Icons.straighten,
                          value: _paper,
                          items: const [
                            DropdownMenuItem(
                                value: '58', child: Text('58 mm')),
                            DropdownMenuItem(
                                value: '80', child: Text('80 mm (recomendado)')),
                          ],
                          onChanged: (v) async {
                            if (v == null) return;
                            setState(() => _paper = v);
                            await _set(_kPaper, v);
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: AppDropdown<String?>(
                                label: 'Impresora predeterminada',
                                icon: Icons.print,
                                value: _printerName,
                                items: _printerItems(),
                                onChanged: (v) async {
                                  setState(() => _printerName = v);
                                  await _set(_kPrinter, v ?? '');
                                  _toast(v == null
                                      ? 'Sin impresora fija (se elige al imprimir)'
                                      : 'Impresora: $v');
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              onPressed: _scanning ? null : _scan,
                              tooltip: 'Buscar impresoras',
                              icon: _scanning
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(Icons.refresh),
                            ),
                          ],
                        ),
                        if (_printers.isEmpty && !_scanning)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'No se detectaron impresoras del sistema. Empareja '
                              'la impresora Bluetooth en Ajustes de Android (o '
                              'conéctala por USB) y toca el botón de recargar. '
                              'También puedes dejar "Ninguna" y elegir al imprimir.',
                              style: TextStyle(fontSize: 12.5),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: _testPrint,
                            icon: const Icon(Icons.print_outlined),
                            label: const Text('Imprimir prueba'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const SectionHeader('Personalización del ticket'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _titleCtrl,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Título (nombre del negocio)',
                            hintText: 'SHELBY CAPS',
                          ),
                          onChanged: (v) =>
                              _set(TicketConfig.kTitle, v.trim()),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _subheadingCtrl,
                          maxLines: 3,
                          minLines: 1,
                          decoration: const InputDecoration(
                            labelText: 'Subtítulo',
                            hintText:
                                'Dirección, teléfono o eslogan (varias líneas)',
                          ),
                          onChanged: (v) =>
                              _set(TicketConfig.kSubheading, v),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _footerCtrl,
                          maxLines: 2,
                          minLines: 1,
                          decoration: const InputDecoration(
                            labelText: 'Leyenda final',
                            hintText: '¡Gracias por su compra!',
                          ),
                          onChanged: (v) => _set(TicketConfig.kFooter, v),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _qrCtrl,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            labelText: 'QR (URL o texto)',
                            hintText:
                                'https://instagram.com/tu_boutique — vacío = sin QR',
                          ),
                          onChanged: (v) => _set(TicketConfig.kQr, v.trim()),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'WhatsApp del negocio',
                            hintText: '899 703 4922',
                            helperText:
                                'Se imprime en la nota de servicio, para que el '
                                'cliente sepa a dónde escribir',
                          ),
                          onChanged: (v) =>
                              _set(TicketConfig.kBusinessPhone, v.trim()),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _addressCtrl,
                          maxLines: 2,
                          minLines: 1,
                          decoration: const InputDecoration(
                            labelText: 'Ubicación del negocio',
                            hintText: 'Calle Monterrey 455 Col. Rdz',
                            helperText: 'También se imprime en la nota de servicio',
                          ),
                          onChanged: (v) =>
                              _set(TicketConfig.kBusinessAddress, v.trim()),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Los cambios se guardan solos. Usa la vista previa para '
                          'ver cómo queda el ticket.',
                          style: TextStyle(fontSize: 12.5),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: _previewTicket,
                            icon: const Icon(Icons.receipt_long),
                            label: const Text('Vista previa'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Vivía dentro de la pantalla del producto, donde no pintaba
                // nada: es una prueba de hardware, como la impresión de prueba.
                const SectionHeader('Lector de códigos'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                            'Dispara el lector sobre una etiqueta. Si el código '
                            'aparece aquí y encuentra el producto, el lector ya '
                            'quedó configurado.',
                            style: TextStyle(fontSize: 12)),
                        const SizedBox(height: 10),
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'Escanea o teclea un código + Enter',
                            prefixIcon: Icon(Icons.qr_code_scanner),
                          ),
                          onSubmitted: _testScan,
                        ),
                        if (_scanResult != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(_scanResult!),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const SectionHeader('Cajón de dinero'),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Abrir el cajón al cobrar en efectivo'),
                        subtitle: const Text(
                            'Requiere una impresora térmica ESC/POS con puerto '
                            'para cajón (RJ11). El cajón se abre con la señal de '
                            'la impresora.'),
                        value: _openDrawer,
                        onChanged: (v) async {
                          setState(() => _openDrawer = v);
                          await _set(_kDrawer, v ? '1' : '0');
                        },
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: AppDropdown<String>(
                          label: 'Pin de apertura del cajón',
                          icon: Icons.cable,
                          value: _drawerPin,
                          items: const [
                            DropdownMenuItem(
                                value: '2',
                                child: Text('Estándar (pin 2) — recomendado')),
                            DropdownMenuItem(
                                value: '5', child: Text('Alternativo (pin 5)')),
                          ],
                          onChanged: (v) async {
                            if (v == null) return;
                            setState(() => _drawerPin = v);
                            await _set(_kDrawerPin, v);
                          },
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Text(
                          'La mayoría de impresoras (incluida la Qian recomendada) '
                          'usan el pin 2. Si al cobrar el cajón no abre, cambia a '
                          'pin 5. Aplica con la impresión ESC/POS directa.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.bar,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Nota técnica: hoy los tickets se imprimen como PDF al sistema '
                    '(eliges impresora en el diálogo de Android). La impresión '
                    'térmica ESC/POS DIRECTA por Bluetooth y la apertura real del '
                    'cajón se activan al integrar el modelo de impresora — dinos '
                    'cuál compraste y lo conectamos.',
                    style: TextStyle(fontSize: 12.5),
                  ),
                ),
              ],
            ),
    );
  }
}

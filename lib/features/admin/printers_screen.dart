import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../data/local/database.dart';

/// Admin → Impresoras. Configura la impresora de tickets (ancho de papel),
/// muestra las impresoras del sistema (Android / Bluetooth emparejadas) para
/// elegir una por defecto, permite una impresión de prueba, y guarda si el
/// cajón de dinero debe abrirse al cobrar en efectivo.
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

  static const _kPaper = 'printer_paper_mm';
  static const _kDrawer = 'printer_open_drawer';
  static const _kPrinter = 'printer_name';

  String _paper = '80';
  bool _openDrawer = false;
  String? _printerName;
  List<Printer> _printers = const [];
  bool _scanning = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _scan();
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
    if (!mounted) return;
    setState(() {
      _paper = paper ?? '80';
      _openDrawer = drawer == '1';
      _printerName = printer;
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
                  pw.Text('Montana Boutique',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Impresoras')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Impresora de tickets',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('Ancho de papel'),
                            const Spacer(),
                            DropdownButton<String>(
                              value: _paper,
                              items: const [
                                DropdownMenuItem(
                                    value: '58', child: Text('58 mm')),
                                DropdownMenuItem(
                                    value: '80', child: Text('80 mm')),
                              ],
                              onChanged: (v) async {
                                if (v == null) return;
                                setState(() => _paper = v);
                                await _set(_kPaper, v);
                              },
                            ),
                          ],
                        ),
                        const Divider(),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _printerName == null
                                    ? 'Sin impresora por defecto'
                                    : 'Por defecto: $_printerName',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _scanning ? null : _scan,
                              icon: _scanning
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(Icons.refresh),
                              label: const Text('Buscar'),
                            ),
                          ],
                        ),
                        if (_printers.isEmpty && !_scanning)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'No se detectaron impresoras del sistema. Empareja '
                              'la impresora Bluetooth en Ajustes de Android, o '
                              'conéctala por USB, y vuelve a "Buscar".',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        for (final p in _printers)
                          ListTile(
                            dense: true,
                            leading: Icon(_printerName == p.name
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked),
                            title: Text(p.name),
                            onTap: () async {
                              setState(() => _printerName = p.name);
                              await _set(_kPrinter, p.name);
                              _toast('Impresora por defecto: ${p.name}');
                            },
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
                Text('Cajón de dinero',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
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
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.shade50,
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

import 'package:flutter/material.dart';

/// Teclado numérico reutilizable para capturar un PIN.
///
/// [onSubmit] recibe el PIN capturado y devuelve un mensaje de error para
/// mostrar en pantalla, o `null` si todo salió bien. El pad se limpia después
/// de cada intento.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.title,
    required this.onSubmit,
    this.subtitle,
    this.minLength = 4,
    this.maxLength = 6,
    this.submitLabel = 'Entrar',
  });

  final String title;
  final String? subtitle;
  final int minLength;
  final int maxLength;
  final String submitLabel;
  final Future<String?> Function(String pin) onSubmit;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _pin = '';
  String? _error;
  bool _busy = false;

  void _tap(String digit) {
    if (_busy || _pin.length >= widget.maxLength) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
  }

  void _backspace() {
    if (_busy || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    if (_busy || _pin.length < widget.minLength) return;
    setState(() => _busy = true);
    final error = await widget.onSubmit(_pin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _pin = '';
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSubmit = _pin.length >= widget.minLength && !_busy;

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title, style: theme.textTheme.headlineSmall),
            if (widget.subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                widget.subtitle!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 24),
            _Dots(length: _pin.length, max: widget.maxLength),
            const SizedBox(height: 12),
            SizedBox(
              height: 24,
              child: _error == null
                  ? null
                  : Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
            ),
            const SizedBox(height: 12),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.6,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var d = 1; d <= 9; d++)
                  _Key(label: '$d', onTap: () => _tap('$d')),
                _Key(icon: Icons.backspace_outlined, onTap: _backspace),
                _Key(label: '0', onTap: () => _tap('0')),
                _Key(
                  icon: Icons.check_circle,
                  onTap: canSubmit ? _submit : null,
                  filled: true,
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: canSubmit ? _submit : null,
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(widget.submitLabel),
            ),
          ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.length, required this.max});

  final int length;
  final int max;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < max; i++)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 6),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < length ? scheme.primary : Colors.transparent,
              border: Border.all(color: scheme.outline),
            ),
          ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({this.label, this.icon, this.onTap, this.filled = false});

  final String? label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final child = icon != null
        ? Icon(icon, size: 28)
        : Text(
            label ?? '',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w500),
          );
    return Material(
      color: filled ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Center(child: child),
      ),
    );
  }
}

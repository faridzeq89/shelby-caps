import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Teclado numérico reutilizable para capturar un PIN.
///
/// Las teclas responden al **tocar** (onTapDown), no al soltar, para que no se
/// pierdan toques rápidos, con vibración ligera de confirmación.
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
    this.logo,
    this.minLength = 4,
    this.maxLength = 6,
    this.submitLabel = 'Entrar',
  });

  final String title;
  final String? subtitle;
  final Widget? logo;
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
                  if (widget.logo != null) ...[
                    widget.logo!,
                    const SizedBox(height: 20),
                  ],
                  Text(widget.title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      widget.subtitle!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: 28),
                  _Dots(length: _pin.length, max: widget.maxLength),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 24,
                    child: _error == null
                        ? null
                        : Text(
                            _error!,
                            style: TextStyle(
                                color: theme.colorScheme.error,
                                fontWeight: FontWeight.w600),
                          ),
                  ),
                  const SizedBox(height: 10),
                  GridView.count(
                    shrinkWrap: true,
                    crossAxisCount: 3,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 1.25,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      for (var d = 1; d <= 9; d++)
                        _Key(label: '$d', onTap: () => _tap('$d')),
                      _Key(
                          icon: Icons.backspace_outlined,
                          onTap: _pin.isEmpty ? null : _backspace),
                      _Key(label: '0', onTap: () => _tap('0')),
                      _Key(
                        icon: Icons.arrow_forward_rounded,
                        onTap: canSubmit ? _submit : null,
                        filled: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: canSubmit ? _submit : null,
                      child: _busy
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(widget.submitLabel),
                    ),
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
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: const EdgeInsets.symmetric(horizontal: 7),
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < length ? scheme.primary : Colors.transparent,
              border: Border.all(
                  color: i < length ? scheme.primary : scheme.outline,
                  width: 1.5),
            ),
          ),
      ],
    );
  }
}

/// Tecla del pad: responde al TOCAR (onTapDown) para no perder toques rápidos,
/// con vibración y realce al presionar.
class _Key extends StatefulWidget {
  const _Key({this.label, this.icon, this.onTap, this.filled = false});

  final String? label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool filled;

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _down = false;

  void _fire() {
    if (widget.onTap == null) return;
    HapticFeedback.lightImpact();
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = widget.onTap != null;
    final child = widget.icon != null
        ? Icon(widget.icon,
            size: 30,
            color: widget.filled ? Colors.white : scheme.onSurface)
        : Text(
            widget.label ?? '',
            style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface),
          );

    final baseColor = widget.filled
        ? scheme.primary
        : Theme.of(context).colorScheme.surface;
    final pressedColor = widget.filled
        ? scheme.primary.withValues(alpha: 0.82)
        : scheme.primary.withValues(alpha: 0.12);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Dispara al TOCAR (down): instantáneo y sin perder toques rápidos.
      onTapDown: enabled
          ? (_) {
              _fire();
              setState(() => _down = true);
            }
          : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        decoration: BoxDecoration(
          color: enabled
              ? (_down ? pressedColor : baseColor)
              : scheme.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: widget.filled ? Colors.transparent : scheme.outlineVariant),
        ),
        child: Center(child: Opacity(opacity: enabled ? 1 : 0.4, child: child)),
      ),
    );
  }
}

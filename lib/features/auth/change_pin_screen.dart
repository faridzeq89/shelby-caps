import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_controller.dart';
import 'pin_pad.dart';

/// Cambio de PIN obligatorio (primer arranque del admin o reseteo). Pide el
/// nuevo PIN dos veces antes de guardarlo.
class ChangePinScreen extends StatefulWidget {
  const ChangePinScreen({super.key});

  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen> {
  String? _firstPin;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthController>();
    final confirming = _firstPin != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Cambiar PIN')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: PinPad(
            // La key fuerza a reconstruir el pad (y limpiar el estado) al pasar
            // de "nuevo" a "confirmar".
            key: ValueKey(confirming),
            title: confirming ? 'Confirma el PIN' : 'Define un PIN nuevo',
            subtitle: confirming
                ? 'Vuelve a escribirlo para confirmar'
                : 'Elige un PIN de 4 a 6 dígitos',
            submitLabel: confirming ? 'Guardar' : 'Continuar',
            onSubmit: (pin) async {
              if (!confirming) {
                setState(() => _firstPin = pin);
                return null;
              }
              if (pin != _firstPin) {
                setState(() => _firstPin = null);
                return 'Los PIN no coinciden, empieza de nuevo';
              }
              await auth.changePin(pin);
              return null;
            },
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../services/motd_settings.dart';

/// Mensaje motivador del día, a **pantalla completa, fondo negro y texto
/// blanco** (como lo pidió el dueño). Se cierra al tocar el botón o el fondo.
/// No usa el tema de la app a propósito: es un respiro de arranque, no una
/// pantalla más del POS.
Future<void> showDailyMotd(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar',
    barrierColor: Colors.black,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, _, _) => _MotdView(phrase: MotdSettings.phraseForToday()),
    transitionBuilder: (_, anim, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
      child: child,
    ),
  );
}

class _MotdView extends StatelessWidget {
  const _MotdView({required this.phrase});
  final String phrase;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).maybePop(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                const Text(
                  'BUENOS DÍAS, JEFE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  phrase,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 27,
                    height: 1.3,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text(
                    '¡A DARLE!',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Toca donde sea para cerrar',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

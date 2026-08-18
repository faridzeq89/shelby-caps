import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ui_kit.dart';
import '../../services/auth_controller.dart';
import '../../services/session_settings.dart';

/// Ajustes → Acceso: prender o apagar el **acceso directo** (entrar sin
/// teclear el PIN).
///
/// No quita el login: lo salta al arrancar. La pantalla dice con todas sus
/// letras qué se gana y qué se pierde, porque es lo único de la app que
/// cambia quién puede tomar el aparato y entrar.
class AccessScreen extends StatelessWidget {
  const AccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionSettings>();
    final user = context.watch<AuthController>().currentUser;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Acceso')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: SwitchListTile(
              value: session.enabled,
              onChanged: user == null
                  ? null
                  : (v) => v
                      ? context.read<SessionSettings>().enableFor(user.id)
                      : context.read<SessionSettings>().disable(),
              title: const Text('Entrar sin PIN',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(session.enabled
                  ? 'La app abre directo como ${user?.name ?? 'este usuario'}'
                  : 'Apagado: se teclea el PIN cada vez que abre la app'),
            ),
          ),
          const SizedBox(height: 16),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Qué cambia',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text(
                  'Prendido, la app abre en Inicio sin pedir nada. En la '
                  'versión web es donde más se nota: cada vez que el navegador '
                  'recarga la pestaña, hoy vuelve a pedir el PIN.',
                ),
                const SizedBox(height: 10),
                const Text(
                  'La pantalla de PIN no desaparece: sigue ahí para "Cerrar '
                  'sesión" cuando le prestes el aparato a alguien más, y '
                  'vuelve sola si este usuario se desactiva.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          WarningBanner(
            icon: Icons.lock_open_outlined,
            title: 'Lo que dejas de tener',
            message: 'Con esto prendido, quien tome la tablet o el teléfono '
                'entra como dueño: ve costos, edita precios y puede cancelar '
                'ventas. La única barrera que queda es el bloqueo del propio '
                'aparato. Si algún día atiende alguien más el mostrador, '
                'apaga este interruptor.',
          ),
        ],
      ),
    );
  }
}

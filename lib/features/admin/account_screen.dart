import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/ui_kit.dart';
import '../../data/local/open_db.dart';
import '../../services/cloud_backup_service.dart';

/// Cuenta del negocio: inicia sesión con correo y contraseña para **acceder a
/// tus datos desde otro equipo**. No es para trabajar al mismo tiempo en dos
/// lados; es para poder continuar en otra tablet/teléfono. Cada cuenta respalda
/// en su carpeta privada de la nube; al entrar en un equipo vacío, baja solos
/// tus datos.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late final CloudBackupService _backup = context.read<CloudBackupService>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;

  SupabaseClient get _auth => Supabase.instance.client;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  String _friendlyAuthError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('invalid login')) return 'Correo o contraseña incorrectos.';
    if (s.contains('already registered') || s.contains('already been registered')) {
      return 'Ese correo ya tiene cuenta. Usa "Iniciar sesión".';
    }
    if (s.contains('password') && s.contains('6')) {
      return 'La contraseña debe tener al menos 6 caracteres.';
    }
    if (s.contains('unable to validate email') || s.contains('invalid email')) {
      return 'El correo no es válido.';
    }
    return 'No se pudo: $e';
  }

  Future<void> _signIn({required bool crear}) async {
    final email = _email.text.trim();
    final pass = _password.text;
    if (!email.contains('@') || email.length < 5) {
      _toast('Escribe un correo válido');
      return;
    }
    if (pass.length < 6) {
      _toast('La contraseña debe tener al menos 6 caracteres');
      return;
    }
    setState(() => _busy = true);
    try {
      if (crear) {
        final res = await _auth.auth.signUp(email: email, password: pass);
        if (res.session == null) {
          // Con auto-confirmación esto no debería pasar; por si acaso.
          _toast('Cuenta creada. Ahora inicia sesión.');
          setState(() => _busy = false);
          return;
        }
      } else {
        await _auth.auth.signInWithPassword(email: email, password: pass);
      }
      await _afterSignIn();
    } catch (e) {
      if (mounted) _toast(_friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Tras iniciar sesión, decide qué hacer con los datos.
  Future<void> _afterSignIn() async {
    final outcome = await _backup.syncOnSignIn();
    if (!mounted) return;
    switch (outcome) {
      case SignInSync.restored:
        await _restartDialog(
            'Descargamos los datos de tu cuenta. Cierra y vuelve a abrir la app '
            'para usarlos.');
      case SignInSync.backedUp:
        _toast('Cuenta lista. Ya puedes entrar con este correo en otro equipo.');
        setState(() {});
      case SignInSync.needsChoice:
        await _resolveConflict();
      case SignInSync.nothing:
        _toast('Cuenta lista. Vende y se respaldará solo.');
        setState(() {});
    }
  }

  /// Este equipo tiene datos y la cuenta también: el dueño elige cuál gana.
  Future<void> _resolveConflict() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Este equipo ya tiene datos'),
        content: const Text(
            'Tu cuenta ya tiene un respaldo y este equipo también tiene datos. '
            '¿Cuál quieres conservar?\n\n'
            '• Descargar los de la cuenta: reemplaza lo de ESTE equipo.\n'
            '• Subir los de este equipo: reemplaza el respaldo de la cuenta.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'download'),
            child: const Text('Descargar los de la cuenta'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'upload'),
            child: const Text('Subir los de este equipo'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    setState(() => _busy = true);
    try {
      if (choice == 'download') {
        await _backup.accountDownload();
        if (mounted) {
          await _restartDialog(
              'Descargamos los datos de tu cuenta. Cierra y vuelve a abrir la '
              'app para usarlos.');
        }
      } else {
        await _backup.uploadThisDevice();
        if (mounted) _toast('Subimos los datos de este equipo a tu cuenta.');
      }
    } catch (e) {
      if (mounted) _toast('No se pudo: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restartDialog(String msg) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Datos descargados'),
        content: Text(msg),
        actions: [
          if (kIsWeb)
            FilledButton(
              onPressed: () => reloadApp(),
              child: const Text('Reiniciar ahora'),
            )
          else
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido'),
            ),
        ],
      ),
    );
  }

  Future<void> _uploadNow() async {
    setState(() => _busy = true);
    try {
      await _backup.uploadThisDevice();
      // En web la app se recarga sola tras subir; en nativo seguimos aquí.
      if (mounted) _toast('Datos de este equipo subidos a tu cuenta.');
    } catch (e) {
      if (mounted) _toast('No se pudo subir: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadNow() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Descargar mis datos'),
        content: const Text(
            'Reemplaza los datos de este equipo con el último respaldo de tu '
            'cuenta. ¿Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Descargar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _backup.accountDownload();
      if (mounted) {
        await _restartDialog(
            'Listo. Cierra y vuelve a abrir la app para usar tus datos.');
      }
    } catch (e) {
      if (mounted) {
        final msg = e is StateError ? e.message : 'No se pudo: $e';
        _toast(msg);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cerrar sesión de la cuenta'),
        content: const Text(
            'Los datos de este equipo se quedan aquí; solo se desconecta la '
            'cuenta. ¿Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cerrar sesión')),
        ],
      ),
    );
    if (ok != true) return;
    await _auth.auth.signOut();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final signedIn = _backup.isSignedIn;
    return Scaffold(
      appBar: AppBar(title: const Text('Cuenta del negocio')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            WarningBanner(
              icon: Icons.devices_outlined,
              title: signedIn ? 'Cuenta conectada' : 'Accede desde otro equipo',
              message: signedIn
                  ? 'Entra con este mismo correo en otro equipo para continuar '
                      'con tus datos.'
                  : 'Inicia sesión para poder acceder a tus datos desde otro '
                      'equipo. No es para trabajar al mismo tiempo en dos lados.',
            ),
            const SizedBox(height: 16),
            if (signedIn) ..._signedInView(theme) else ..._signInForm(theme),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _signInForm(ThemeData theme) => [
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Correo',
            hintText: 'tucorreo@ejemplo.com',
            prefixIcon: Icon(Icons.mail_outline),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: !_showPassword,
          decoration: InputDecoration(
            labelText: 'Contraseña',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(
                  _showPassword ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : () => _signIn(crear: false),
            icon: const Icon(Icons.login),
            label: const Text('Iniciar sesión'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : () => _signIn(crear: true),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Crear cuenta nueva'),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Usa un correo y una contraseña que recuerdes: son la llave para '
          'entrar a tus datos en cualquier equipo.',
          style: theme.textTheme.bodySmall,
        ),
      ];

  List<Widget> _signedInView(ThemeData theme) => [
        SurfaceCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.verified_user_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_backup.accountEmail ?? 'Cuenta',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('Sesión iniciada en este equipo.',
                  style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : _uploadNow,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('Subir los cambios de este equipo'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _downloadNow,
            icon: const Icon(Icons.cloud_download_outlined),
            label: const Text('Descargar mis datos ahora'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: _busy ? null : _signOut,
            icon: Icon(Icons.logout, color: theme.colorScheme.error),
            label: Text('Cerrar sesión',
                style: TextStyle(color: theme.colorScheme.error)),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Tus ventas se respaldan solas a tu cuenta. En otro equipo, entra con '
          'este correo y tus datos bajan automáticamente.',
          style: theme.textTheme.bodySmall,
        ),
      ];
}

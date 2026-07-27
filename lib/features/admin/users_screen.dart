import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_dropdown.dart';
import '../../data/local/database.dart';
import '../../data/repositories/user_repository.dart';
import '../../services/auth_controller.dart';

String roleLabel(UserRole r) => switch (r) {
      UserRole.admin => 'Administrador',
      UserRole.manager => 'Gerente',
      UserRole.cashier => 'Cajero',
    };

Color roleColor(UserRole r) => switch (r) {
      UserRole.admin => Colors.deepPurple,
      UserRole.manager => Colors.teal,
      UserRole.cashier => Colors.blueGrey,
    };

Widget _chip(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  late final UserRepository _repo = UserRepository(context.read<AppDatabase>());
  late Future<List<Profile>> _future = _repo.listUsers();
  String _query = '';
  UserRole? _roleFilter;

  Profile get _actor => context.read<AuthController>().currentUser!;

  Widget _roleChips() {
    Widget rc(String label, UserRole? r) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(label),
            selected: _roleFilter == r,
            onSelected: (_) => setState(() => _roleFilter = r),
          ),
        );
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          rc('Todos', null),
          for (final r in UserRole.values) rc(roleLabel(r), r),
        ],
      ),
    );
  }

  void _reload() => setState(() => _future = _repo.listUsers());

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _addUser() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _UserFormDialog(repo: _repo, actor: _actor),
    );
    if (created == true) {
      _reload();
      _toast('Usuario creado. Debe cambiar su PIN al primer ingreso.');
    }
  }

  Future<void> _resetPin(Profile u) async {
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => _PinDialog(title: 'Nuevo PIN para ${u.name}'),
    );
    if (pin == null) return;
    try {
      await _repo.resetPin(_actor, u.id, pin);
      _toast('PIN reiniciado. ${u.name} lo cambiará al ingresar.');
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _toggleActive(Profile u) async {
    try {
      await _repo.setActive(_actor, u.id, !u.active);
      _reload();
    } catch (e) {
      _toast('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Usuarios')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addUser,
        icon: const Icon(Icons.person_add),
        label: const Text('Nuevo usuario'),
      ),
      body: FutureBuilder<List<Profile>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final q = _query.trim().toLowerCase();
          final users = snap.data!.where((u) {
            if (_roleFilter != null && u.role != _roleFilter) return false;
            if (q.isNotEmpty && !u.name.toLowerCase().contains(q)) return false;
            return true;
          }).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    hintText: 'Buscar por nombre…',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              _roleChips(),
              Expanded(
                child: users.isEmpty
                    ? const Center(child: Text('Sin resultados'))
                    : ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
            itemCount: users.length,
            itemBuilder: (context, i) {
              final u = users[i];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: roleColor(u.role).withValues(alpha: 0.18),
                  child: Text(
                    u.name.isNotEmpty ? u.name[0].toUpperCase() : '?',
                    style: TextStyle(
                        color: roleColor(u.role),
                        fontWeight: FontWeight.w700),
                  ),
                ),
                title: Text(u.name,
                    style: TextStyle(
                        fontWeight: FontWeight.w500,
                        decoration:
                            u.active ? null : TextDecoration.lineThrough)),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _chip(roleLabel(u.role), roleColor(u.role)),
                      if (!u.active) _chip('Inactivo', Colors.grey),
                      if (u.mustChangePin)
                        _chip('PIN por cambiar', Colors.orange.shade800),
                    ],
                  ),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'pin') _resetPin(u);
                    if (v == 'toggle') _toggleActive(u);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'pin', child: Text('Reiniciar PIN')),
                    PopupMenuItem(
                        value: 'toggle',
                        child: Text(u.active ? 'Desactivar' : 'Activar')),
                  ],
                ),
              ),
              );
            },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Alta de usuario: nombre, rol y PIN inicial.
class _UserFormDialog extends StatefulWidget {
  const _UserFormDialog({required this.repo, required this.actor});
  final UserRepository repo;
  final Profile actor;

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  final _name = TextEditingController();
  final _pin = TextEditingController();
  UserRole _role = UserRole.cashier;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repo.createUser(
        widget.actor,
        name: _name.text,
        role: _role,
        pin: _pin.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuevo usuario'),
      content: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nombre'),
          ),
          const SizedBox(height: 12),
          AppDropdown<UserRole>(
            label: 'Rol',
            value: _role,
            items: [
              for (final r in UserRole.values)
                DropdownMenuItem(value: r, child: Text(roleLabel(r))),
            ],
            onChanged: (v) => setState(() => _role = v ?? UserRole.cashier),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pin,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 6,
            decoration: const InputDecoration(
                labelText: 'PIN inicial (4-6 dígitos)'),
          ),
          if (_error != null)
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Crear'),
        ),
      ],
    );
  }
}

/// Captura de un PIN (para reinicio).
class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.title});
  final String title;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _pin = TextEditingController();

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _pin,
        autofocus: true,
        keyboardType: TextInputType.number,
        obscureText: true,
        maxLength: 6,
        decoration: const InputDecoration(labelText: 'PIN (4-6 dígitos)'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_pin.text.trim()),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

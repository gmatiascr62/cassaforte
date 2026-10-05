import 'package:flutter/material.dart';

import '../../model/vault_entry.dart';
import '../app_scope.dart';
import '../vault_actions.dart';
import '../widgets/common.dart';
import '../widgets/generator_sheet.dart';
import 'entry_detail_screen.dart';
import 'entry_form_screen.dart';
import 'settings_screen.dart';

/// Lista de cuentas con búsqueda.
class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showPending());
  }

  Future<void> _showPending() async {
    if (!mounted) return;
    final pending = AppScope.read(context).pending;
    if (pending.reenableBiometric) {
      pending
        ..reenableBiometric = false
        ..offerBiometric = false;
      showMessage(
        context,
        'Cambiaron las huellas o el bloqueo del teléfono: '
        'confirmá para volver a activar la huella.',
      );
      await enableBiometric(context);
    } else if (pending.offerBiometric) {
      pending.offerBiometric = false;
      await offerBiometric(context);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(VaultEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EntryDetailScreen(entryId: entry.id),
      ),
    );
  }

  Future<void> _add() async {
    final id = await Navigator.of(
      context,
    ).push(MaterialPageRoute<String>(builder: (_) => const EntryFormScreen()));
    if (id != null && mounted) showMessage(context, 'Cuenta guardada.');
  }

  Future<void> _generator() async {
    final value = await showPasswordGenerator(
      context,
      actionLabel: 'Copiar contraseña',
    );
    if (value != null && mounted) await copySecret(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final all = scope.session.entries;
    final visible = all.where((e) => e.matches(_query)).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cassaforte'),
        actions: [
          IconButton(
            tooltip: 'Generador de contraseñas',
            icon: const Icon(Icons.password),
            onPressed: _generator,
          ),
          IconButton(
            tooltip: 'Ajustes y copias',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Bloquear',
            icon: const Icon(Icons.lock),
            onPressed: scope.session.lock,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Añadir'),
      ),
      body: SafeArea(
        child: CenteredBody(
          maxWidth: 720,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: SearchBar(
                  controller: _search,
                  hintText: 'Buscar cuentas',
                  leading: const Icon(Icons.search),
                  elevation: const WidgetStatePropertyAll(0),
                  trailing: [
                    if (_query.isNotEmpty)
                      IconButton(
                        tooltip: 'Borrar búsqueda',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
                  ],
                  onChanged: (v) {
                    scope.session.registerActivity();
                    setState(() => _query = v);
                  },
                ),
              ),
              Expanded(
                child: all.isEmpty
                    ? const _EmptyState(
                        icon: Icons.inventory_2_outlined,
                        text:
                            'Aún no hay cuentas.\nPulsa «Añadir» para '
                            'guardar la primera.',
                      )
                    : visible.isEmpty
                    ? const _EmptyState(
                        icon: Icons.search_off,
                        text: 'Ninguna cuenta coincide con la búsqueda.',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: visible.length,
                        itemBuilder: (context, i) {
                          final entry = visible[i];
                          return _EntryTile(
                            entry: entry,
                            onTap: () => _open(entry),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.onTap});

  final VaultEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = entry.username.isNotEmpty ? entry.username : entry.url;
    final initial = entry.title.trim().isEmpty
        ? '?'
        : entry.title.trim().characters.first.toUpperCase();
    return ListTile(
      leading: CircleAvatar(child: Text(initial)),
      title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: IconButton(
        tooltip: 'Copiar contraseña',
        icon: const Icon(Icons.copy),
        onPressed: () => copySecret(context, entry.password),
      ),
      onTap: onTap,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

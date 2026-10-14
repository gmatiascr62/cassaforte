import 'package:flutter/material.dart';

import '../../model/vault_entry.dart';
import '../../session/vault_session.dart';
import '../app_scope.dart';
import '../vault_actions.dart';
import '../widgets/common.dart';
import '../widgets/generator_sheet.dart';
import 'entry_detail_screen.dart';
import 'entry_form_screen.dart';
import 'settings_screen.dart';
import 'terms_screen.dart';

/// Lista de cuentas con búsqueda.
class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final _search = TextEditingController();
  String _query = '';

  VaultSession? _session;
  bool _wasUnlocked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = AppScope.read(context).session;
    if (!identical(session, _session)) {
      _session?.removeListener(_onSessionChanged);
      _session = session..addListener(_onSessionChanged);
      _onSessionChanged();
    }
  }

  /// Los avisos pendientes se muestran cada vez que se abre la bóveda.
  void _onSessionChanged() {
    final unlocked = _session!.isUnlocked;
    if (unlocked && !_wasUnlocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showPending());
    }
    _wasUnlocked = unlocked;
  }

  Future<void> _showPending() async {
    if (!mounted || !(_session?.isUnlocked ?? false)) return;
    // Bóvedas creadas antes de los Términos de uso (o con una versión
    // anterior): hay que aceptarlos para seguir.
    if (!await _ensureTermsAccepted() || !mounted) return;
    final pending = AppScope.read(context).pending;
    final restored = pending.restoredCount;
    if (restored != null) {
      pending.restoredCount = null;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle_outline),
          title: const Text('Restauración completada'),
          content: Text(
            'Se recuperaron $restored cuenta(s). Tu contraseña maestra es la '
            'que usaste para abrir la copia.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Aceptar'),
            ),
          ],
        ),
      );
      if (!mounted) return;
    }
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

  Future<bool> _ensureTermsAccepted() async {
    final scope = AppScope.read(context);
    if (await scope.terms.isAccepted()) return true;
    if (!mounted) return false;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          icon: const Icon(Icons.gavel_outlined),
          title: const Text('Términos de uso'),
          content: const Text(
            'Para seguir usando Cassaforte, leé y aceptá los Términos de uso. '
            'La app se ofrece gratis y «tal cual», y vos sos responsable de '
            'la seguridad de tu teléfono, tu contraseña maestra y tus copias.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const TermsScreen()),
              ),
              child: const Text('Leer'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('No acepto'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Acepto'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true) {
      await scope.terms.accept();
      return true;
    }
    // Sin aceptar no se puede usar: se vuelve a bloquear.
    scope.session.lock();
    return false;
  }

  @override
  void dispose() {
    _session?.removeListener(_onSessionChanged);
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
    if (id != null && mounted) showMessage(context, 'Guardado.');
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
                  hintText: 'Buscar',
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
                            'Todavía no guardaste nada.\nPulsa «Añadir» '
                            'para guardar una sesión, una tarjeta o un '
                            'contacto.',
                      )
                    : visible.isEmpty
                    ? const _EmptyState(
                        icon: Icons.search_off,
                        text: 'Nada coincide con la búsqueda.',
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
    final subtitle = switch (entry.type) {
      EntryType.login => entry.username.isNotEmpty ? entry.username : entry.url,
      EntryType.card => [
        if (entry.detail('number').isNotEmpty)
          maskCardNumber(entry.detail('number')),
        if (entry.detail('expiry').isNotEmpty) entry.detail('expiry'),
      ].join(' · '),
      EntryType.contact =>
        entry.detail('phone').isNotEmpty
            ? entry.detail('phone')
            : entry.detail('email'),
    };
    // Lo que copia el botón de la lista, según el tipo.
    final (copyTooltip, copyValue, copied) = switch (entry.type) {
      EntryType.login => (
        'Copiar contraseña',
        entry.password,
        'Contraseña copiada',
      ),
      EntryType.card => (
        'Copiar número de tarjeta',
        entry.detail('number').replaceAll(RegExp(r'[ -]'), ''),
        'Número de tarjeta copiado',
      ),
      EntryType.contact => (
        'Copiar contacto',
        entry.contactText(),
        'Contacto copiado',
      ),
    };
    return ListTile(
      leading: CircleAvatar(child: Icon(entryTypeIcon(entry.type))),
      title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: copyValue.isEmpty
          ? null
          : IconButton(
              tooltip: copyTooltip,
              icon: const Icon(Icons.copy),
              onPressed: () => copySecret(context, copyValue, what: copied),
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

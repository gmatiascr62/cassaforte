import 'package:flutter/material.dart';

import '../../model/vault_entry.dart';
import '../../session/vault_session.dart';
import '../app_scope.dart';
import '../widgets/common.dart';
import 'entry_form_screen.dart';

/// Consulta de un elemento. La contraseña y los datos ocultos (número de
/// tarjeta, código de seguridad) están ocultos por defecto.
class EntryDetailScreen extends StatefulWidget {
  const EntryDetailScreen({super.key, required this.entryId});

  final String entryId;

  @override
  State<EntryDetailScreen> createState() => _EntryDetailScreenState();
}

class _EntryDetailScreenState extends State<EntryDetailScreen> {
  bool _visible = false;

  /// Campos adicionales ocultos que el usuario decidió mostrar.
  final Set<int> _revealed = {};

  /// Datos propios ocultos (número de tarjeta, código) que se mostraron.
  final Set<String> _revealedDetails = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Al bloquearse la bóveda, todo vuelve a ocultarse.
    if (!AppScope.of(context).session.isUnlocked) {
      _visible = false;
      _revealed.clear();
      _revealedDetails.clear();
    }
  }

  Widget _copyButton(String value, String tooltip, String what) => IconButton(
    tooltip: tooltip,
    icon: const Icon(Icons.copy),
    onPressed: () => copySecret(context, value, what: what),
  );

  Future<void> _edit(VaultEntry entry) async {
    await Navigator.of(context).push(
      MaterialPageRoute<String>(builder: (_) => EntryFormScreen(entry: entry)),
    );
  }

  Future<void> _delete(VaultEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: Text('¿Eliminar ${_noun(entry.type)}?'),
        content: Text(
          'Se eliminará «${entry.title}» de la bóveda. '
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final session = AppScope.read(context).session;
    try {
      await session.deleteEntry(entry.id);
      if (!mounted) return;
      showMessage(context, 'Eliminado: «${entry.title}».');
      Navigator.of(context).pop();
    } on VaultLockedException {
      // La pantalla se cierra al bloquearse.
    } catch (_) {
      if (mounted) showMessage(context, 'No se pudo eliminar.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = AppScope.of(context).session.entryById(widget.entryId);
    if (entry == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Ya no existe.')),
      );
    }
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(entry.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _edit(entry),
          ),
          IconButton(
            tooltip: 'Eliminar',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(entry),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            CenteredBody(
              child: Column(
                children: [
                  _Field(label: 'Nombre', value: entry.title),
                  if (entry.username.isNotEmpty)
                    _Field(
                      label: 'Usuario',
                      value: entry.username,
                      trailing: _copyButton(
                        entry.username,
                        'Copiar usuario',
                        'Usuario copiado',
                      ),
                    ),
                  // Cuentas guardadas con versiones anteriores.
                  if (entry.url.isNotEmpty)
                    _Field(label: 'Dirección web', value: entry.url),
                  for (final spec in entry.type.details)
                    if (entry.detail(spec.key).isNotEmpty)
                      _detailField(entry, spec),
                  for (final (i, field) in entry.fields.indexed)
                    _Field(
                      label: field.label,
                      value: field.hidden && !_revealed.contains(i)
                          ? '••••••••'
                          : field.value,
                      monospace: field.hidden && _revealed.contains(i),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (field.hidden)
                            IconButton(
                              tooltip: _revealed.contains(i)
                                  ? 'Ocultar ${field.label}'
                                  : 'Mostrar ${field.label}',
                              icon: Icon(
                                _revealed.contains(i)
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () {
                                AppScope.read(context).session
                                    .registerActivity();
                                setState(() {
                                  if (!_revealed.remove(i)) _revealed.add(i);
                                });
                              },
                            ),
                          _copyButton(
                            field.value,
                            'Copiar ${field.label}',
                            '${field.label}: copiado',
                          ),
                        ],
                      ),
                    ),
                  if (entry.notes.isNotEmpty)
                    _Field(label: 'Notas', value: entry.notes),
                  // La contraseña siempre va al final.
                  if (entry.type == EntryType.login)
                    _Field(
                      label: 'Contraseña',
                      value: _visible ? entry.password : '••••••••••••',
                      monospace: _visible,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          VisibilityToggle(
                            visible: _visible,
                            onChanged: (v) {
                              AppScope.read(context).session.registerActivity();
                              setState(() => _visible = v);
                            },
                          ),
                          IconButton(
                            tooltip: 'Copiar contraseña',
                            icon: const Icon(Icons.copy),
                            onPressed: () =>
                                copySecret(context, entry.password),
                          ),
                        ],
                      ),
                    ),
                  if (entry.type == EntryType.contact)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          onPressed: () => copySecret(
                            context,
                            entry.contactText(),
                            what: 'Contacto copiado',
                          ),
                          icon: const Icon(Icons.copy_all),
                          label: const Text('Copiar contacto entero'),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Modificada: ${_formatDate(entry.updatedAt)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Un dato propio del tipo: con copiar y, si es oculto, mostrar.
  Widget _detailField(VaultEntry entry, DetailSpec spec) {
    final value = entry.detail(spec.key);
    final revealed = _revealedDetails.contains(spec.key);
    final isNumber = spec.key == 'number';
    return _Field(
      label: spec.label,
      value: !spec.hidden || revealed
          ? (isNumber ? groupCardNumber(value) : value)
          : (isNumber ? maskCardNumber(value) : '•••'),
      monospace: spec.hidden && revealed,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (spec.hidden)
            IconButton(
              tooltip: revealed
                  ? 'Ocultar ${spec.label.toLowerCase()}'
                  : 'Mostrar ${spec.label.toLowerCase()}',
              icon: Icon(revealed ? Icons.visibility_off : Icons.visibility),
              onPressed: () {
                AppScope.read(context).session.registerActivity();
                setState(() {
                  if (!_revealedDetails.remove(spec.key)) {
                    _revealedDetails.add(spec.key);
                  }
                });
              },
            ),
          _copyButton(
            // El número se copia sin espacios, como lo piden los formularios
            // de pago.
            isNumber ? value.replaceAll(RegExp(r'[ -]'), '') : value,
            'Copiar ${spec.label.toLowerCase()}',
            '${spec.label}: copiado',
          ),
        ],
      ),
    );
  }

  static String _noun(EntryType type) => switch (type) {
    EntryType.login => 'la sesión',
    EntryType.card => 'la tarjeta',
    EntryType.contact => 'el contacto',
  };

  static String _formatDate(DateTime utc) {
    final d = utc.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} '
        '${two(d.hour)}:${two(d.minute)}';
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    this.trailing,
    this.monospace = false,
  });

  final String label;
  final String value;
  final Widget? trailing;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label, style: Theme.of(context).textTheme.labelMedium),
      subtitle: SelectableText(
        value,
        style: Theme.of(context).textTheme.bodyLarge
            ?.copyWith(fontFamily: monospace ? 'monospace' : null),
      ),
      trailing: trailing,
    );
  }
}

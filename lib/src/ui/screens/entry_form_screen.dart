import 'package:flutter/material.dart';

import '../../model/vault_entry.dart';
import '../../session/vault_session.dart';
import '../app_scope.dart';
import '../widgets/common.dart';
import '../widgets/generator_sheet.dart';

/// Formulario para añadir o editar una cuenta: nombre, usuario, campos
/// adicionales opcionales y, siempre al final, la contraseña.
class EntryFormScreen extends StatefulWidget {
  const EntryFormScreen({super.key, this.entry});

  /// Cuenta a editar, o `null` para crear una nueva.
  final VaultEntry? entry;

  @override
  State<EntryFormScreen> createState() => _EntryFormScreenState();
}

/// Controladores de un campo adicional.
class _ExtraField {
  _ExtraField({String label = '', String value = '', this.hidden = false})
    : label = TextEditingController(text: label),
      value = TextEditingController(text: value);

  final Key key = UniqueKey();
  final TextEditingController label;
  final TextEditingController value;
  bool hidden;
  bool revealed = false;

  void dispose() {
    label
      ..clear()
      ..dispose();
    value
      ..clear()
      ..dispose();
  }
}

class _EntryFormScreenState extends State<EntryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.entry?.title);
  late final _username = TextEditingController(text: widget.entry?.username);
  late final _password = TextEditingController(text: widget.entry?.password);
  late final List<_ExtraField> _extras = _initialExtras();
  bool _visible = false;
  bool _saving = false;

  /// Campos adicionales de la cuenta. La dirección web y las notas de
  /// cuentas creadas con versiones anteriores pasan a ser campos adicionales.
  List<_ExtraField> _initialExtras() {
    final entry = widget.entry;
    if (entry == null) return [];
    return [
      if (entry.url.isNotEmpty)
        _ExtraField(label: 'Dirección web', value: entry.url),
      for (final f in entry.fields)
        _ExtraField(label: f.label, value: f.value, hidden: f.hidden),
      if (entry.notes.isNotEmpty)
        _ExtraField(label: 'Notas', value: entry.notes),
    ];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Al bloquearse la bóveda, los valores ocultos vuelven a ocultarse.
    if (!AppScope.of(context).session.isUnlocked) {
      _visible = false;
      for (final f in _extras) {
        f.revealed = false;
      }
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _username, _password]) {
      c
        ..clear()
        ..dispose();
    }
    for (final f in _extras) {
      f.dispose();
    }
    super.dispose();
  }

  void _addField() {
    AppScope.read(context).session.registerActivity();
    setState(() => _extras.add(_ExtraField()));
  }

  void _removeField(_ExtraField field) {
    setState(() => _extras.remove(field));
    // Se libera después de que el campo deje de mostrarse.
    WidgetsBinding.instance.addPostFrameCallback((_) => field.dispose());
  }

  Future<void> _generate() async {
    final value = await showPasswordGenerator(context);
    if (value != null && mounted) {
      setState(() {
        _password.text = value;
        _visible = true;
      });
    }
  }

  List<CustomField> _collectFields() => [
    for (final f in _extras)
      if (f.label.text.trim().isNotEmpty || f.value.text.isNotEmpty)
        CustomField(
          label: f.label.text.trim(),
          value: f.value.text,
          hidden: f.hidden,
        ),
  ];

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final session = AppScope.read(context).session;
    final existing = widget.entry;
    final fields = _collectFields();
    final entry = existing == null
        ? VaultEntry.create(
            title: _title.text.trim(),
            username: _username.text.trim(),
            password: _password.text,
            fields: fields,
          )
        : existing.copyWith(
            title: _title.text.trim(),
            username: _username.text.trim(),
            password: _password.text,
            fields: fields,
            // Ya están incluidas como campos adicionales.
            url: '',
            notes: '',
          );
    setState(() => _saving = true);
    try {
      await session.saveEntry(entry);
      if (!mounted) return;
      Navigator.of(context).pop(entry.id);
    } on VaultLockedException {
      // Lo escrito se conserva; se puede volver a guardar al desbloquear.
    } catch (_) {
      if (mounted) {
        showMessage(context, 'No se pudo guardar. No se ha perdido nada.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _extraFieldEditor(_ExtraField field) {
    final theme = Theme.of(context);
    return Card(
      key: field.key,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: SecureTextField(
                    controller: field.label,
                    label: 'Nombre del campo',
                    textInputAction: TextInputAction.next,
                    validator: (v) =>
                        (v ?? '').trim().isEmpty && field.value.text.isNotEmpty
                        ? 'Ponele un nombre (ej.: PIN).'
                        : null,
                  ),
                ),
                IconButton(
                  tooltip: 'Quitar campo',
                  icon: const Icon(Icons.close),
                  onPressed: () => _removeField(field),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SecureTextField(
                controller: field.value,
                label: 'Valor',
                obscure: field.hidden && !field.revealed,
                textInputAction: TextInputAction.next,
                suffix: field.hidden
                    ? VisibilityToggle(
                        visible: field.revealed,
                        onChanged: (v) => setState(() => field.revealed = v),
                      )
                    : null,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() {
                  field.hidden = !field.hidden;
                  field.revealed = false;
                }),
                icon: Icon(
                  field.hidden ? Icons.lock_outline : Icons.lock_open_outlined,
                  size: 18,
                ),
                label: Text(
                  field.hidden
                      ? 'Oculto como una contraseña'
                      : 'Visible (tocá para ocultarlo)',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.entry != null;
    // Con la bóveda bloqueada, el botón «atrás» no cierra el formulario
    // oculto: lo escrito sigue ahí al desbloquear.
    final locked = !AppScope.of(context).session.isUnlocked;
    return PopScope(
      canPop: !locked,
      child: Scaffold(
        appBar: AppBar(
          title: Text(editing ? 'Editar cuenta' : 'Nueva cuenta'),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
              child: const Text('Guardar'),
            ),
          ],
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                CenteredBody(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SecureTextField(
                        controller: _title,
                        label: 'Nombre *',
                        helperText: 'Por ejemplo: Banco, Correo, Netflix…',
                        autofocus: !editing,
                        textInputAction: TextInputAction.next,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Indicá un nombre.'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      SecureTextField(
                        controller: _username,
                        label: 'Usuario',
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 12),
                      for (final field in _extras) _extraFieldEditor(field),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: _addField,
                          icon: const Icon(Icons.add),
                          label: const Text('Añadir campo'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SecureTextField(
                        controller: _password,
                        label: 'Contraseña *',
                        obscure: !_visible,
                        monospace: _visible,
                        textInputAction: TextInputAction.done,
                        validator: (v) => (v == null || v.isEmpty)
                            ? 'Indicá la contraseña.'
                            : null,
                        suffix: VisibilityToggle(
                          visible: _visible,
                          onChanged: (v) => setState(() => _visible = v),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _generate,
                          icon: const Icon(Icons.auto_awesome),
                          label: const Text('Generar contraseña'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(_saving ? 'Guardando…' : 'Guardar'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

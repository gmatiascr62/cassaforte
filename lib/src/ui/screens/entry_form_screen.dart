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

/// Un campo adicional: su nombre (elegido al añadirlo) y su valor.
class _ExtraField {
  _ExtraField({required this.label, String value = '', this.hidden = false})
    : value = TextEditingController(text: value);

  final Key key = UniqueKey();
  final String label;
  final TextEditingController value;
  final bool hidden;
  bool revealed = false;

  void dispose() {
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

  /// Pide el nombre del campo y lo añade vacío, antes de la contraseña.
  Future<void> _addField() async {
    AppScope.read(context).session.registerActivity();
    final result = await showDialog<({String label, bool hidden})>(
      context: context,
      builder: (_) => const _NewFieldDialog(),
    );
    if (result == null || !mounted) return;
    setState(
      () =>
          _extras.add(_ExtraField(label: result.label, hidden: result.hidden)),
    );
  }

  Future<void> _confirmRemove(_ExtraField field) async {
    if (field.value.text.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('¿Quitar «${field.label}»?'),
          content: const Text('Se borrará lo que escribiste en este campo.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Quitar'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    _removeField(field);
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
      if (f.value.text.isNotEmpty)
        CustomField(label: f.label, value: f.value.text, hidden: f.hidden),
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

  /// Mismo estilo que «Usuario» y «Contraseña»; el nombre del campo es su
  /// etiqueta. A la derecha: mostrar (si es oculto) y quitar.
  Widget _extraFieldEditor(_ExtraField field) {
    return Padding(
      key: field.key,
      padding: const EdgeInsets.only(bottom: 12),
      child: SecureTextField(
        controller: field.value,
        label: field.label,
        obscure: field.hidden && !field.revealed,
        monospace: field.hidden && field.revealed,
        textInputAction: TextInputAction.next,
        suffix: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (field.hidden)
              IconButton(
                tooltip: field.revealed
                    ? 'Ocultar ${field.label}'
                    : 'Mostrar ${field.label}',
                icon: Icon(
                  field.revealed ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () =>
                    setState(() => field.revealed = !field.revealed),
              ),
            IconButton(
              tooltip: 'Quitar ${field.label}',
              icon: const Icon(Icons.close),
              onPressed: () => _confirmRemove(field),
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
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              onPressed: _addField,
                              icon: const Icon(Icons.add),
                              label: const Text('Añadir campo'),
                            ),
                            TextButton.icon(
                              onPressed: _generate,
                              icon: const Icon(Icons.auto_awesome),
                              label: const Text('Generar contraseña'),
                            ),
                          ],
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

/// Alerta que pide el nombre del campo nuevo.
class _NewFieldDialog extends StatefulWidget {
  const _NewFieldDialog();

  @override
  State<_NewFieldDialog> createState() => _NewFieldDialogState();
}

class _NewFieldDialogState extends State<_NewFieldDialog> {
  final _name = TextEditingController();
  bool _hidden = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Escribí un nombre.');
      return;
    }
    Navigator.of(context).pop((label: name, hidden: _hidden));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuevo campo'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            autocorrect: false,
            enableIMEPersonalizedLearning: false,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Nombre del campo',
              hintText: 'Ej.: PIN, Número de cliente',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _hidden,
            onChanged: (v) => setState(() => _hidden = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Ocultarlo como una contraseña'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Añadir')),
      ],
    );
  }
}

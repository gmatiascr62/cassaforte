import 'package:flutter/material.dart';

import '../../model/vault_entry.dart';
import '../../session/vault_session.dart';
import '../app_scope.dart';
import '../widgets/common.dart';
import '../widgets/generator_sheet.dart';

/// Formulario para añadir o editar una cuenta.
class EntryFormScreen extends StatefulWidget {
  const EntryFormScreen({super.key, this.entry});

  /// Cuenta a editar, o `null` para crear una nueva.
  final VaultEntry? entry;

  @override
  State<EntryFormScreen> createState() => _EntryFormScreenState();
}

class _EntryFormScreenState extends State<EntryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.entry?.title);
  late final _url = TextEditingController(text: widget.entry?.url);
  late final _username = TextEditingController(text: widget.entry?.username);
  late final _password = TextEditingController(text: widget.entry?.password);
  late final _notes = TextEditingController(text: widget.entry?.notes);
  bool _visible = false;
  bool _saving = false;

  List<TextEditingController> get _controllers => [
    _title,
    _url,
    _username,
    _password,
    _notes,
  ];

  @override
  void dispose() {
    for (final c in _controllers) {
      c.clear();
      c.dispose();
    }
    super.dispose();
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final session = AppScope.read(context).session;
    final existing = widget.entry;
    final entry = existing == null
        ? VaultEntry.create(
            title: _title.text.trim(),
            url: _url.text.trim(),
            username: _username.text.trim(),
            password: _password.text,
            notes: _notes.text,
          )
        : existing.copyWith(
            title: _title.text.trim(),
            url: _url.text.trim(),
            username: _username.text.trim(),
            password: _password.text,
            notes: _notes.text,
          );
    setState(() => _saving = true);
    try {
      await session.saveEntry(entry);
      if (!mounted) return;
      Navigator.of(context).pop(entry.id);
    } on VaultLockedException {
      // La pantalla se cierra al bloquearse la bóveda.
    } catch (_) {
      if (mounted) {
        showMessage(context, 'No se pudo guardar. No se ha perdido nada.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.entry != null;
    return Scaffold(
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
                      label: 'Nombre de la página *',
                      autofocus: !editing,
                      textInputAction: TextInputAction.next,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Indica el nombre de la página.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    SecureTextField(
                      controller: _url,
                      label: 'Dirección web',
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    SecureTextField(
                      controller: _username,
                      label: 'Usuario o correo',
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    SecureTextField(
                      controller: _password,
                      label: 'Contraseña *',
                      obscure: !_visible,
                      monospace: _visible,
                      textInputAction: TextInputAction.next,
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Indica la contraseña.'
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
                    const SizedBox(height: 4),
                    SecureTextField(
                      controller: _notes,
                      label: 'Notas (opcional)',
                      maxLines: 6,
                    ),
                    const SizedBox(height: 24),
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
    );
  }
}

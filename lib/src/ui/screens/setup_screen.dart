import 'package:flutter/material.dart';

import '../../session/vault_session.dart';
import '../app_scope.dart';
import '../widgets/common.dart';

/// Primera ejecución: crea la bóveda con una contraseña maestra confirmada.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _visible = false;
  bool _accepted = false;
  String? _error;

  @override
  void dispose() {
    _password.clear();
    _confirm.clear();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    if (!_accepted) {
      setState(() => _error = 'Debes confirmar que has leído el aviso.');
      return;
    }
    final session = AppScope.read(context).session;
    try {
      await session.create(_password.text);
    } on VaultLockedException {
      // La aplicación pasó a segundo plano: la sesión queda bloqueada.
    } on VaultAlreadyExistsException {
      if (mounted) {
        setState(() => _error = 'Ya existe una bóveda; no se ha sobrescrito.');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No se pudo crear la bóveda. Inténtalo de nuevo.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = AppScope.of(context).session.isBusy;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Crear bóveda')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: CenteredBody(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 56,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Bienvenido a Cassaforte',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tus cuentas se guardan cifradas solo en este teléfono. '
                    'Elige una contraseña maestra larga que puedas recordar; '
                    'una frase de varias palabras es una buena opción.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  const RecoveryWarning(),
                  const SizedBox(height: 16),
                  SecureTextField(
                    controller: _password,
                    label: 'Contraseña maestra',
                    obscure: !_visible,
                    enabled: !busy,
                    textInputAction: TextInputAction.next,
                    helperText:
                        'Mínimo ${VaultSession.minMasterPasswordLength} caracteres.',
                    suffix: VisibilityToggle(
                      visible: _visible,
                      onChanged: (v) => setState(() => _visible = v),
                    ),
                    validator: (v) {
                      if (v == null ||
                          v.length < VaultSession.minMasterPasswordLength) {
                        return 'Usa al menos '
                            '${VaultSession.minMasterPasswordLength} caracteres.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  SecureTextField(
                    controller: _confirm,
                    label: 'Repite la contraseña maestra',
                    obscure: !_visible,
                    enabled: !busy,
                    textInputAction: TextInputAction.done,
                    validator: (v) => v != _password.text
                        ? 'Las contraseñas no coinciden.'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: _accepted,
                    onChanged: busy
                        ? null
                        : (v) => setState(() => _accepted = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Entiendo que si olvido la contraseña maestra o pierdo '
                      'los datos del móvil no podré recuperar la bóveda.',
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: busy ? null : _create,
                    icon: busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_outline),
                    label: Text(
                      busy ? 'Protegiendo la bóveda…' : 'Crear bóveda',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

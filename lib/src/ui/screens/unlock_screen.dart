import 'package:flutter/material.dart';

import '../../session/vault_session.dart';
import '../app_scope.dart';
import '../widgets/common.dart';

/// Pide la contraseña maestra para abrir la bóveda.
class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _password = TextEditingController();
  bool _visible = false;
  String? _error;

  @override
  void dispose() {
    _password.clear();
    _password.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final password = _password.text;
    if (password.isEmpty) {
      setState(() => _error = 'Escribe la contraseña maestra.');
      return;
    }
    setState(() => _error = null);
    final session = AppScope.read(context).session;
    String? error;
    try {
      await session.unlock(password);
    } on WrongPasswordException {
      error = 'Contraseña incorrecta o archivo alterado.';
    } on VaultCorruptedException {
      error =
          'El archivo de la bóveda está dañado o no es válido. '
          'No se ha modificado.';
    } on VaultLockedException {
      // Se bloqueó durante el desbloqueo (p. ej., pasó a segundo plano).
    } catch (_) {
      error = 'No se pudo abrir la bóveda.';
    }
    if (!mounted) return;
    _password.clear();
    setState(() => _error = error);
  }

  @override
  Widget build(BuildContext context) {
    final busy = AppScope.of(context).session.isBusy;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: CenteredBody(
              maxWidth: 440,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 64,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Cassaforte',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'La bóveda está bloqueada.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  SecureTextField(
                    controller: _password,
                    label: 'Contraseña maestra',
                    obscure: !_visible,
                    enabled: !busy,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => busy ? null : _unlock(),
                    suffix: VisibilityToggle(
                      visible: _visible,
                      onChanged: (v) => setState(() => _visible = v),
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
                    onPressed: busy ? null : _unlock,
                    icon: busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_open),
                    label: Text(busy ? 'Abriendo…' : 'Desbloquear'),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Si olvidas la contraseña maestra no hay forma de '
                    'recuperar la bóveda.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
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

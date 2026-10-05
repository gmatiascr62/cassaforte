import 'package:flutter/material.dart';

import '../../security/biometric_unlock.dart';
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
  bool _biometricEnabled = false;
  bool _autoPrompted = false;
  bool _prompting = false;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Muestra el diálogo de huella al volver a la aplicación (una vez).
    _lifecycle = AppLifecycleListener(onResume: _maybeAutoPrompt);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBiometric());
  }

  Future<void> _loadBiometric() async {
    if (!mounted) return;
    final enabled = await AppScope.read(context).biometric.isEnabled();
    if (!mounted) return;
    setState(() => _biometricEnabled = enabled);
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _maybeAutoPrompt();
    }
  }

  void _maybeAutoPrompt() {
    if (!_biometricEnabled || _autoPrompted || !mounted) return;
    _autoPrompted = true;
    _unlockWithBiometric();
  }

  Future<void> _unlockWithBiometric() async {
    if (_prompting) return;
    final scope = AppScope.read(context);
    if (scope.session.isBusy) return;
    setState(() {
      _prompting = true;
      _error = null;
    });
    String? error;
    try {
      await scope.runExternal(() => scope.biometric.unlock(scope.session));
    } on BiometricCanceledException {
      // El usuario prefirió la contraseña.
    } on BiometricInvalidatedException {
      scope.pending.reenableBiometric = true;
      _biometricEnabled = false;
      error =
          'Cambiaron las huellas o el bloqueo de pantalla del teléfono y '
          'Android anuló la llave por seguridad. Escribí la contraseña '
          'maestra; después vas a poder volver a activar la huella.';
    } on BiometricFailedException catch (e) {
      error = 'No se pudo usar la huella: ${e.message}';
    } on VaultCorruptedException {
      error =
          'El archivo de la bóveda está dañado o no es válido. '
          'No se ha modificado.';
    } on VaultLockedException {
      // Se bloqueó durante el desbloqueo.
    } catch (_) {
      error = 'No se pudo abrir la bóveda con la huella.';
    }
    if (!mounted) return;
    setState(() {
      _prompting = false;
      _error = error;
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
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
    final busy = AppScope.of(context).session.isBusy || _prompting;
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
                  if (_biometricEnabled) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: busy || _prompting
                          ? null
                          : _unlockWithBiometric,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Usar huella o patrón'),
                    ),
                  ],
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

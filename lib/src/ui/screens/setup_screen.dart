import 'package:flutter/material.dart';

import '../../session/vault_session.dart';
import '../app_scope.dart';
import '../widgets/common.dart';
import 'recovery_screen.dart';
import 'terms_screen.dart';

/// Primera ejecución: crear una bóveda nueva o recuperar las cuentas desde
/// una copia de seguridad.
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
  bool _termsAccepted = false;

  /// Mostrando el formulario de «Crear bóveda nueva».
  bool _creating = false;
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
    if (!_termsAccepted) {
      setState(() => _error = 'Debes aceptar los Términos de uso.');
      return;
    }
    final scope = AppScope.read(context);
    final session = scope.session;
    try {
      await scope.terms.accept();
      // Una llave de huella de una bóveda anterior ya no sirve.
      await scope.biometric.disable();
      scope.pending.offerBiometric = true;
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

  bool _checkTerms() {
    if (_termsAccepted) return true;
    setState(() => _error = 'Primero aceptá los Términos de uso.');
    return false;
  }

  Future<void> _recover() async {
    if (!_checkTerms()) return;
    setState(() => _error = null);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const RecoveryScreen(mode: RecoveryMode.setup),
      ),
    );
  }

  Widget _termsCheckbox(bool busy) => CheckboxListTile(
    value: _termsAccepted,
    onChanged: busy
        ? null
        : (v) => setState(() {
            _termsAccepted = v ?? false;
            _error = null;
          }),
    controlAffinity: ListTileControlAffinity.leading,
    contentPadding: EdgeInsets.zero,
    title: const Text('Leí y acepto los Términos de uso.'),
    subtitle: Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        ),
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => const TermsScreen())),
        child: const Text('Leer los Términos de uso'),
      ),
    ),
  );

  Widget _errorText(ThemeData theme) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
  );

  /// Pantalla inicial: crear o recuperar.
  List<Widget> _choice(ThemeData theme, bool busy) => [
    Icon(Icons.shield_outlined, size: 56, color: theme.colorScheme.primary),
    const SizedBox(height: 12),
    Text(
      'Bienvenido a Cassaforte',
      textAlign: TextAlign.center,
      style: theme.textTheme.headlineSmall,
    ),
    const SizedBox(height: 8),
    const Text(
      'Tus cuentas se guardan cifradas solo en este teléfono.',
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 16),
    const RecoveryWarning(),
    const SizedBox(height: 8),
    _termsCheckbox(busy),
    if (_error != null) _errorText(theme),
    const SizedBox(height: 16),
    FilledButton.icon(
      onPressed: busy
          ? null
          : () {
              if (_checkTerms()) setState(() => _creating = true);
            },
      icon: const Icon(Icons.add_moderator_outlined),
      label: const Text('Crear bóveda nueva'),
    ),
    const SizedBox(height: 12),
    OutlinedButton.icon(
      onPressed: busy ? null : _recover,
      icon: const Icon(Icons.restore),
      label: const Text('Recuperar mis contraseñas'),
    ),
    const SizedBox(height: 8),
    Text(
      'Usá «Recuperar» si tenés una copia de seguridad en PDF (o impresa) '
      'de otro teléfono.',
      textAlign: TextAlign.center,
      style: theme.textTheme.bodySmall,
    ),
  ];

  /// Formulario de la contraseña maestra.
  List<Widget> _createForm(ThemeData theme, bool busy) => [
    const Text(
      'Elegí una contraseña maestra larga que puedas recordar; una frase de '
      'varias palabras es una buena opción.',
    ),
    const SizedBox(height: 16),
    SecureTextField(
      controller: _password,
      label: 'Contraseña maestra',
      obscure: !_visible,
      enabled: !busy,
      autofocus: true,
      textInputAction: TextInputAction.next,
      helperText: 'Mínimo ${VaultSession.minMasterPasswordLength} caracteres.',
      suffix: VisibilityToggle(
        visible: _visible,
        onChanged: (v) => setState(() => _visible = v),
      ),
      validator: (v) {
        if (v == null || v.length < VaultSession.minMasterPasswordLength) {
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
      validator: (v) =>
          v != _password.text ? 'Las contraseñas no coinciden.' : null,
    ),
    const SizedBox(height: 8),
    CheckboxListTile(
      value: _accepted,
      onChanged: busy ? null : (v) => setState(() => _accepted = v ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      title: const Text(
        'Entiendo que si olvido la contraseña maestra o pierdo '
        'los datos del móvil no podré recuperar la bóveda.',
      ),
    ),
    if (_error != null) _errorText(theme),
    const SizedBox(height: 16),
    FilledButton.icon(
      onPressed: busy ? null : _create,
      icon: busy
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.lock_outline),
      label: Text(busy ? 'Protegiendo la bóveda…' : 'Crear bóveda'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final busy = AppScope.of(context).session.isBusy;
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_creating,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !busy) setState(() => _creating = false);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_creating ? 'Crear bóveda' : 'Cassaforte'),
          leading: _creating
              ? BackButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          _creating = false;
                          _error = null;
                        }),
                )
              : null,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: CenteredBody(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _creating
                      ? _createForm(theme, busy)
                      : _choice(theme, busy),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

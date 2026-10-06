import 'package:flutter/material.dart';

import '../../security/biometric_unlock.dart';
import '../app_scope.dart';
import '../vault_actions.dart';
import '../widgets/common.dart';
import 'security_info_screen.dart';
import 'terms_screen.dart';

/// Ajustes: desbloqueo con huella y copias de seguridad.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  BiometricAvailability? _availability;
  bool _enabled = false;
  bool _working = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_availability == null) _refresh();
  }

  Future<void> _refresh() async {
    final biometric = AppScope.read(context).biometric;
    BiometricAvailability availability;
    try {
      availability = await biometric.availability();
    } catch (_) {
      availability = BiometricAvailability.error;
    }
    final enabled = await biometric.isEnabled();
    if (mounted) {
      setState(() {
        _availability = availability;
        _enabled = enabled;
      });
    }
  }

  Future<void> _toggle(bool value) async {
    setState(() => _working = true);
    if (value) {
      await enableBiometric(context);
    } else {
      await AppScope.read(context).biometric.disable();
      if (mounted) showMessage(context, 'Desbloqueo con huella desactivado.');
    }
    await _refresh();
    if (mounted) setState(() => _working = false);
  }

  @override
  Widget build(BuildContext context) {
    final availability = _availability;
    final available = availability == BiometricAvailability.available;
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: SafeArea(
        child: ListView(
          children: [
            CenteredBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Header('Desbloqueo'),
                  SwitchListTile(
                    secondary: const Icon(Icons.fingerprint),
                    title: const Text('Huella o patrón del teléfono'),
                    subtitle: Text(
                      availability == null
                          ? 'Comprobando…'
                          : available || _enabled
                          ? 'Abrí la bóveda sin escribir la contraseña maestra. '
                                'Si cambian las huellas del teléfono se pedirá '
                                'la contraseña maestra.'
                          : biometricUnavailableText(availability),
                    ),
                    isThreeLine: true,
                    value: _enabled,
                    onChanged: _working || (!available && !_enabled)
                        ? null
                        : _toggle,
                  ),
                  const Divider(),
                  const _Header('Copias de seguridad'),
                  ListTile(
                    leading: const Icon(Icons.upload_file),
                    title: const Text('Exportar copia'),
                    subtitle: const Text(
                      'Archivo cifrado con tu contraseña maestra. Guardalo '
                      'fuera del teléfono para no perder tus claves.',
                    ),
                    onTap: () => exportBackup(context),
                  ),
                  ListTile(
                    leading: const Icon(Icons.download),
                    title: const Text('Importar copia'),
                    subtitle: const Text(
                      'Fusiona o reemplaza las cuentas con las de un archivo '
                      'de copia.',
                    ),
                    onTap: () => importBackup(context),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.gavel_outlined),
                    title: const Text('Términos de uso'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const TermsScreen(),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('Seguridad y limitaciones'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SecurityInfoScreen(),
                      ),
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
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

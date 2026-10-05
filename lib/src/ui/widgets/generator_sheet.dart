import 'package:flutter/material.dart';

import '../../security/password_generator.dart';
import '../app_scope.dart';

/// Muestra el generador. Devuelve la contraseña elegida o `null`.
Future<String?> showPasswordGenerator(
  BuildContext context, {
  String actionLabel = 'Usar esta contraseña',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => GeneratorSheet(actionLabel: actionLabel),
  );
}

class GeneratorSheet extends StatefulWidget {
  const GeneratorSheet({super.key, required this.actionLabel});

  final String actionLabel;

  @override
  State<GeneratorSheet> createState() => _GeneratorSheetState();
}

class _GeneratorSheetState extends State<GeneratorSheet> {
  PasswordOptions _options = const PasswordOptions();
  String _password = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_password.isEmpty) _regenerate();
  }

  void _regenerate() {
    final scope = AppScope.read(context);
    scope.session.registerActivity();
    _password = _options.hasAnySet ? scope.generator.generate(_options) : '';
  }

  void _update(PasswordOptions options) {
    setState(() {
      _options = options;
      _regenerate();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bits = PasswordGenerator.estimateEntropyBits(_options).round();
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Generador de contraseñas',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            _password.isEmpty
                                ? 'Elige al menos un tipo de carácter'
                                : _password,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 18,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Generar otra',
                          icon: const Icon(Icons.refresh),
                          onPressed: () => setState(_regenerate),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Entropía aproximada: $bits bits',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Text('Longitud: ${_options.length}'),
                Slider(
                  value: _options.length.toDouble(),
                  min: PasswordOptions.minLength.toDouble(),
                  max: PasswordOptions.maxLength.toDouble(),
                  divisions:
                      PasswordOptions.maxLength - PasswordOptions.minLength,
                  label: '${_options.length}',
                  onChanged: (v) =>
                      _update(_options.copyWith(length: v.round())),
                ),
                SwitchListTile(
                  title: const Text('Minúsculas (a-z)'),
                  value: _options.lowercase,
                  onChanged: (v) => _update(_options.copyWith(lowercase: v)),
                ),
                SwitchListTile(
                  title: const Text('Mayúsculas (A-Z)'),
                  value: _options.uppercase,
                  onChanged: (v) => _update(_options.copyWith(uppercase: v)),
                ),
                SwitchListTile(
                  title: const Text('Números (0-9)'),
                  value: _options.digits,
                  onChanged: (v) => _update(_options.copyWith(digits: v)),
                ),
                SwitchListTile(
                  title: const Text('Símbolos (!#\$%…)'),
                  value: _options.symbols,
                  onChanged: (v) => _update(_options.copyWith(symbols: v)),
                ),
                SwitchListTile(
                  title: const Text('Evitar caracteres ambiguos'),
                  subtitle: const Text('Excluye O, 0, o, I, l, 1 y |'),
                  value: _options.avoidAmbiguous,
                  onChanged: (v) =>
                      _update(_options.copyWith(avoidAmbiguous: v)),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _password.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(_password),
                  child: Text(widget.actionLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../backup/qr_backup_cipher.dart';
import '../../backup/qr_backup_service.dart';
import '../../backup/qr_chunks.dart';
import '../../model/vault_entry.dart';
import '../../session/vault_session.dart';
import '../../storage/backup_files.dart';
import '../app_scope.dart';
import '../widgets/common.dart';
import 'qr_scan_screen.dart';

enum RecoveryMode {
  /// Teléfono nuevo: crea la bóveda con las cuentas de la copia.
  setup,

  /// Bóveda abierta: fusiona o reemplaza con las cuentas de la copia.
  import,
}

/// Recupera las cuentas desde la copia en PDF: escaneando sus códigos QR
/// con la cámara o eligiendo el archivo PDF. También acepta los archivos
/// `.cassaforte` de versiones anteriores.
class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key, required this.mode});

  final RecoveryMode mode;

  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  final _assembler = BackupAssembler();
  bool _busy = false;
  String? _progress;
  String? _error;

  bool get _setup => widget.mode == RecoveryMode.setup;

  Future<void> _scan() async {
    setState(() => _error = null);
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => QrScanScreen(assembler: _assembler),
      ),
    );
    if (!mounted) return;
    setState(() {});
    if (_assembler.isComplete) await _decrypt();
  }

  Future<void> _pickFile() async {
    final scope = AppScope.read(context);
    setState(() => _error = null);
    final Uint8List? bytes;
    try {
      bytes = await scope.runExternal(scope.backupFiles.open);
    } on BackupFileException {
      setState(() => _error = 'No se pudo leer el archivo.');
      return;
    }
    if (bytes == null || !mounted) return;
    if (!QrBackupService.looksLikePdf(bytes)) {
      if (scope.session.isVaultFile(bytes)) {
        await _legacyFile(bytes);
      } else {
        setState(
          () => _error =
              'El archivo no es un PDF ni una copia de Cassaforte válida.',
        );
      }
      return;
    }
    setState(() {
      _busy = true;
      _progress = 'Leyendo el PDF…';
    });
    try {
      await scope.qrBackup.readPdf(
        bytes,
        _assembler,
        onProgress: (page, _) {
          if (!mounted) return;
          setState(() {
            _progress =
                'Hoja $page leída · ${_assembler.received} de '
                '${_assembler.total ?? '?'} códigos';
          });
        },
      );
    } on BackupFormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
    if (!mounted) return;
    if (_assembler.isComplete) {
      await _decrypt();
    } else if (_assembler.total != null && _error == null) {
      setState(
        () => _error =
            'Faltan ${_assembler.missing.length} códigos de la copia. Podés '
            'escanearlos con la cámara.',
      );
    }
  }

  /// Pide la contraseña maestra hasta que sea correcta o se cancele.
  Future<void> _decrypt() async {
    final scope = AppScope.read(context);
    final Uint8List payload;
    try {
      payload = _assembler.assemble();
    } on BackupFormatException catch (e) {
      setState(() {
        _error = '${e.message}. Volvé a leer la copia.';
        _assembler.reset();
      });
      return;
    }
    String? message =
        'Escribí la contraseña maestra que tenías cuando hiciste la copia.';
    while (true) {
      if (!mounted) return;
      final password = await showPasswordPrompt(
        context,
        title: 'Contraseña maestra',
        message: message!,
        confirmLabel: 'Recuperar',
      );
      if (password == null || !mounted) return;
      setState(() {
        _busy = true;
        _progress = 'Descifrando la copia…';
      });
      final List<VaultEntry> entries;
      try {
        entries = await scope.qrBackup.open(payload, password);
      } on BackupWrongPasswordException {
        message =
            'Contraseña incorrecta (o la copia está alterada). Probá de '
            'nuevo.';
        continue;
      } on BackupFormatException catch (e) {
        if (mounted) setState(() => _error = e.message);
        return;
      } finally {
        if (mounted) {
          setState(() {
            _busy = false;
            _progress = null;
          });
        }
      }
      if (!mounted) return;
      await _apply(entries, password);
      return;
    }
  }

  Future<void> _apply(List<VaultEntry> entries, String password) async {
    final scope = AppScope.read(context);
    if (_setup) {
      try {
        await scope.terms.accept();
        await scope.biometric.disable();
        scope.pending
          ..offerBiometric = true
          ..restoredCount = entries.length;
        if (!mounted) return;
        setState(() {
          _busy = true;
          _progress = 'Guardando tus cuentas en este teléfono…';
        });
        await scope.session.restoreEntries(entries, password);
        // La app vuelve sola a la pantalla principal al abrirse la bóveda.
      } on VaultAlreadyExistsException {
        scope.pending.restoredCount = null;
        if (mounted) {
          setState(() => _error = 'Ya existe una bóveda; no se sobrescribe.');
        }
      } on VaultLockedException {
        // Se bloqueó mientras tanto: la bóveda quedó guardada.
      } catch (_) {
        scope.pending.restoredCount = null;
        if (mounted) {
          setState(
            () => _error =
                'No se pudo guardar la bóveda. No se modificó nada; '
                'probá de nuevo.',
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _busy = false;
            _progress = null;
          });
        }
      }
    } else {
      await _import(entries);
    }
  }

  Future<void> _import(List<VaultEntry> entries) async {
    final scope = AppScope.read(context);
    final replace = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Importar copia'),
        content: Text(
          'La copia tiene ${entries.length} cuenta(s).\n\n'
          '• Fusionar: añade las que faltan y actualiza las que en la copia '
          'son más recientes.\n'
          '• Reemplazar: borra las cuentas actuales y deja solo las de la '
          'copia.\n\nTu contraseña maestra actual no cambia.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reemplazar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Fusionar'),
          ),
        ],
      ),
    );
    if (replace == null || !mounted) return;
    try {
      final result = await scope.session.importEntries(
        entries,
        replace: replace,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      showMessage(
        context,
        replace
            ? 'Bóveda reemplazada: ${result.added} cuenta(s).'
            : 'Importadas ${result.added} nueva(s) y '
                  '${result.updated} actualizada(s).',
      );
    } on VaultLockedException {
      // Se puede repetir al desbloquear.
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo importar. No se modificó nada.');
      }
    }
  }

  /// Archivo `.cassaforte` de una versión anterior de la aplicación.
  Future<void> _legacyFile(Uint8List bytes) async {
    final scope = AppScope.read(context);
    String? message =
        'Este archivo es una copia de una versión anterior. Escribí la '
        'contraseña maestra con la que se hizo.';
    while (true) {
      if (!mounted) return;
      final password = await showPasswordPrompt(
        context,
        title: 'Abrir copia',
        message: message!,
        confirmLabel: 'Abrir',
      );
      if (password == null || !mounted) return;
      setState(() {
        _busy = true;
        _progress = 'Descifrando la copia…';
      });
      try {
        if (_setup) {
          final entries = await scope.session.openBackup(bytes, password);
          await scope.terms.accept();
          await scope.biometric.disable();
          scope.pending
            ..offerBiometric = true
            ..restoredCount = entries.length;
          await scope.session.restoreBackup(bytes, password);
        } else {
          final entries = await scope.session.openBackup(bytes, password);
          if (!mounted) return;
          setState(() => _busy = false);
          await _import(entries);
        }
        return;
      } on WrongPasswordException {
        message = 'Contraseña incorrecta o archivo alterado. Probá de nuevo.';
      } on VaultCorruptedException {
        scope.pending.restoredCount = null;
        if (mounted) {
          setState(
            () => _error =
                'El archivo no es un PDF ni una copia de Cassaforte válida.',
          );
        }
        return;
      } on VaultAlreadyExistsException {
        scope.pending.restoredCount = null;
        if (mounted) {
          setState(() => _error = 'Ya existe una bóveda; no se sobrescribe.');
        }
        return;
      } on VaultLockedException {
        return;
      } finally {
        if (mounted) {
          setState(() {
            _busy = false;
            _progress = null;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _assembler.total;
    return Scaffold(
      appBar: AppBar(
        title: Text(_setup ? 'Recuperar mis contraseñas' : 'Importar copia'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            CenteredBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Usá la copia de seguridad en PDF que exportaste con '
                    'Cassaforte (o la hoja impresa) y la contraseña maestra '
                    'que tenías al hacerla.',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 16),
                  _OptionCard(
                    icon: Icons.qr_code_scanner,
                    title: 'Escanear códigos QR',
                    subtitle:
                        'Con la cámara, desde la hoja impresa o desde otra '
                        'pantalla. En cualquier orden.',
                    onTap: _busy ? null : _scan,
                  ),
                  const SizedBox(height: 12),
                  _OptionCard(
                    icon: Icons.picture_as_pdf_outlined,
                    title: 'Seleccionar archivo PDF',
                    subtitle:
                        'El PDF de la copia. También acepta archivos '
                        '.cassaforte de versiones anteriores.',
                    onTap: _busy ? null : _pickFile,
                  ),
                  if (total != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      '${_assembler.received} de $total códigos leídos',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: _assembler.received / total),
                    if (!_assembler.isComplete)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                  _assembler.reset();
                                  _error = null;
                                }),
                          child: const Text('Empezar de nuevo'),
                        ),
                      )
                    else
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed: _busy ? null : _decrypt,
                          child: const Text('Continuar'),
                        ),
                      ),
                  ],
                  if (_progress != null) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(_progress!)),
                      ],
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon, size: 32),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        enabled: onTap != null,
        onTap: onTap,
      ),
    );
  }
}

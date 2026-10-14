import 'dart:async';

import 'package:flutter/material.dart';

import '../../backup/qr_backup_service.dart';
import '../../session/vault_session.dart';
import '../../storage/backup_files.dart';
import '../app_scope.dart';
import '../widgets/common.dart';

/// Exporta la copia de seguridad: aviso, contraseña maestra, PDF.
Future<void> exportPdfBackup(BuildContext context) async {
  final scope = AppScope.read(context);
  final proceed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.picture_as_pdf_outlined),
      title: const Text('Exportar copia de seguridad'),
      content: const SingleChildScrollView(
        child: Text(
          'Se va a crear un PDF con códigos QR que contienen todas tus '
          'cuentas, cifradas con tu contraseña maestra actual.\n\n'
          '• Guardalo fuera del teléfono o imprimilo y conservalo en un '
          'lugar seguro: si perdés el teléfono, es la única forma de '
          'recuperar tus cuentas.\n'
          '• Para restaurarlo vas a necesitar la contraseña maestra que '
          'tenés hoy, aunque después la cambies.\n'
          '• Nunca escribas la contraseña maestra en la misma hoja.\n'
          '• La copia no se actualiza sola: volvé a exportarla cuando '
          'agregues o cambies cuentas.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Continuar'),
        ),
      ],
    ),
  );
  if (proceed != true || !context.mounted) return;
  final password = await showPasswordPrompt(
    context,
    title: 'Confirmá tu contraseña maestra',
    message: 'La copia se cifra con esta contraseña.',
    confirmLabel: 'Crear copia',
  );
  if (password == null || !context.mounted) return;

  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Expanded(child: Text('Generando la copia cifrada…')),
            ],
          ),
        ),
      ),
    ),
  );
  void closeProgress() {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }

  final PdfBackup backup;
  try {
    final entries = await scope.session.confirmMasterPassword(password);
    backup = await scope.qrBackup.createPdf(entries, password);
  } on WrongPasswordException {
    closeProgress();
    if (context.mounted) showMessage(context, 'Contraseña incorrecta.');
    return;
  } on VaultLockedException {
    closeProgress();
    return;
  } catch (_) {
    closeProgress();
    if (context.mounted) showMessage(context, 'No se pudo crear la copia.');
    return;
  }
  closeProgress();
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => ExportResultScreen(backup: backup)),
  );
}

/// Copia lista: guardar, imprimir o compartir.
class ExportResultScreen extends StatelessWidget {
  const ExportResultScreen({super.key, required this.backup});

  final PdfBackup backup;

  Future<void> _save(BuildContext context) async {
    final scope = AppScope.read(context);
    try {
      final saved = await scope.runExternal(
        () => scope.backupFiles.save(
          backup.fileName,
          backup.pdf,
          mimeType: 'application/pdf',
        ),
      );
      if (saved && context.mounted) showMessage(context, 'PDF guardado.');
    } on BackupFileException {
      if (context.mounted) showMessage(context, 'No se pudo guardar el PDF.');
    }
  }

  Future<void> _run(
    BuildContext context,
    Future<void> Function(BackupFiles files) action,
  ) async {
    final scope = AppScope.read(context);
    try {
      await scope.runExternal(() => action(scope.backupFiles));
    } on BackupFileException {
      if (context.mounted) showMessage(context, 'No se pudo completar.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Copia de seguridad')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            CenteredBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 56,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Copia lista',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${backup.codes} código(s) QR en ${backup.pages} '
                    'hoja(s) · Copia ${backup.shortId}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.secondaryContainer,
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Guardá el PDF fuera del teléfono (en tu computadora, '
                        'un pendrive o la nube) o imprimilo. Sin esta copia y '
                        'sin tu contraseña maestra no vas a poder recuperar '
                        'tus cuentas en otro teléfono.',
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => _save(context),
                    icon: const Icon(Icons.save_alt),
                    label: const Text('Guardar PDF'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _run(
                      context,
                      (f) => f.print(backup.fileName, backup.pdf),
                    ),
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Imprimir'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _run(
                      context,
                      (f) => f.share(backup.fileName, backup.pdf),
                    ),
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Compartir'),
                  ),
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Listo'),
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

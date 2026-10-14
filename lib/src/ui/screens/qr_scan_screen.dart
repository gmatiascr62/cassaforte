import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../backup/qr_chunks.dart';
import '../../session/vault_session.dart';
import '../app_scope.dart';
import '../qr_scanner.dart';

/// Escanea con la cámara los códigos QR de una copia impresa o en pantalla,
/// en cualquier orden, hasta tenerlos todos.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key, required this.assembler});

  final BackupAssembler assembler;

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  QrScanner? _scanner;
  bool _running = false;
  bool _resumed = true;
  String? _error;
  String _message =
      'Apuntá a un código por vez y acercate hasta que ocupe casi toda la '
      'imagen.';
  late final AppLifecycleListener _lifecycle;

  BackupAssembler get _asm => widget.assembler;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () {
        _resumed = false;
        _sync();
      },
      onShow: () {
        _resumed = true;
        _sync();
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Se vuelve a evaluar cuando cambia la sesión (p. ej., al bloquearse).
    AppScope.of(context);
    _sync();
  }

  /// Enciende la cámara solo si la app está visible, la bóveda no está
  /// bloqueada y faltan códigos.
  void _sync() {
    if (!mounted) return;
    final locked = AppScope.read(context).session.status == VaultStatus.locked;
    final want = _resumed && !locked && !_asm.isComplete && _error == null;
    if (want && !_running) {
      unawaited(_start());
    } else if (!want && _running) {
      unawaited(_stop());
    }
  }

  Future<void> _start() async {
    final scope = AppScope.read(context);
    final scanner = scope.qrScanner();
    _scanner = scanner;
    _running = true;
    try {
      // El permiso de cámara se pide en un diálogo del sistema.
      await scope.runExternal(() => scanner.start(_onCode));
      if (mounted) setState(() {});
    } on QrScannerException catch (e) {
      _running = false;
      _scanner = null;
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _stop() async {
    _running = false;
    final s = _scanner;
    _scanner = null;
    await s?.stop();
  }

  void _onCode(String text) {
    if (!mounted) return;
    final status = _asm.add(text);
    setState(() {
      _message = switch (status) {
        ChunkStatus.added => 'Código leído.',
        ChunkStatus.duplicate => 'Ese código ya estaba leído.',
        ChunkStatus.otherCopy =>
          'Ese código es de otra copia (no coincide con la copia '
              '${_asm.copyIdHex?.substring(0, 4)}…).',
        ChunkStatus.invalid =>
          'No es un código de Cassaforte o no se leyó bien.',
        ChunkStatus.conflict =>
          'Ese código no coincide con uno ya leído: la copia puede estar '
              'alterada.',
      };
    });
    if (status == ChunkStatus.added) {
      unawaited(HapticFeedback.mediumImpact());
      if (_asm.isComplete) {
        unawaited(_stop());
        Navigator.of(context).pop(true);
      }
    }
  }

  void _reset() {
    setState(() {
      _asm.reset();
      _message = 'Empezamos de nuevo: escaneá cualquier código.';
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _asm.total;
    final missing = _asm.missing;
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear códigos QR')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.no_photography_outlined,
                              size: 48,
                              color: theme.colorScheme.error,
                            ),
                            const SizedBox(height: 12),
                            Text(_error!, textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            OutlinedButton(
                              onPressed: () => setState(() {
                                _error = null;
                                _sync();
                              }),
                              child: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ClipRect(
                      child:
                          _scanner?.buildPreview(context) ??
                          const Center(child: CircularProgressIndicator()),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    total == null
                        ? 'Escaneá cualquier código de la copia'
                        : '${_asm.received} de $total códigos escaneados',
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  if (total != null) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: _asm.received / total),
                  ],
                  const SizedBox(height: 8),
                  Text(_message, textAlign: TextAlign.center),
                  if (total != null && missing.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Faltan: ${missing.take(12).join(', ')}'
                      '${missing.length > 12 ? '…' : ''}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  if (total != null) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _reset,
                      child: const Text('Empezar de nuevo'),
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

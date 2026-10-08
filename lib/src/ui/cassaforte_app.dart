import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../backup/qr_backup_service.dart';
import '../legal/terms.dart';
import '../security/biometric_unlock.dart';
import '../security/clipboard_guard.dart';
import '../security/password_generator.dart';
import '../session/vault_session.dart';
import '../storage/backup_files.dart';
import 'app_scope.dart';
import 'external_ui_guard.dart';
import 'qr_scanner.dart';
import 'screens/setup_screen.dart';
import 'screens/unlock_screen.dart';
import 'screens/vault_screen.dart';

class CassaforteApp extends StatefulWidget {
  const CassaforteApp({
    super.key,
    required this.session,
    required this.clipboard,
    required this.biometric,
    required this.terms,
    this.backupFiles = const MethodChannelBackupFiles(),
    QrBackupService? qrBackup,
    QrScannerFactory? qrScanner,
    PasswordGenerator? generator,
  }) : _generator = generator,
       _qrBackup = qrBackup,
       _qrScanner = qrScanner;

  final VaultSession session;
  final ClipboardGuard clipboard;
  final BiometricUnlock biometric;
  final TermsAcceptance terms;
  final BackupFiles backupFiles;
  final PasswordGenerator? _generator;
  final QrBackupService? _qrBackup;
  final QrScannerFactory? _qrScanner;

  @override
  State<CassaforteApp> createState() => _CassaforteAppState();
}

class _CassaforteAppState extends State<CassaforteApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final PasswordGenerator _generator =
      widget._generator ?? PasswordGenerator();
  late final AppLifecycleListener _lifecycle;
  final _externalUi = ExternalUiGuard();
  final _pending = PendingPrompts();
  late final QrBackupService _qrBackup = widget._qrBackup ?? QrBackupService();
  late VaultStatus _lastStatus = widget.session.status;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSessionChanged);
    _lifecycle = AppLifecycleListener(
      // Bloquea en cuanto la aplicación deja de estar visible.
      onHide: _lockIfLeft,
      onPause: _lockIfLeft,
      onResume: () => unawaited(widget.clipboard.onAppResumed()),
    );
  }

  void _lockIfLeft() {
    // Durante el diálogo de huella o el selector de archivos, ver
    // [ExternalUiGuard].
    if (!_externalUi.active) widget.session.lock();
  }

  void _onSessionChanged() {
    final status = widget.session.status;
    if (_lastStatus == VaultStatus.needsSetup &&
        status != VaultStatus.needsSetup) {
      // Bóveda creada o recuperada: se cierran las pantallas de recuperación.
      _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    }
    if (_lastStatus == VaultStatus.unlocked && status != VaultStatus.unlocked) {
      // Las pantallas abiertas (p. ej., un formulario a medio completar) se
      // conservan debajo de la pantalla de bloqueo, ocultas y sin foco, para
      // seguir donde se estaba al desbloquear.
      FocusManager.instance.primaryFocus?.unfocus();
    }
    _lastStatus = status;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    widget.session.removeListener(_onSessionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness brightness) => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1F6F5C),
        brightness: brightness,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    );

    return AppScope(
      session: widget.session,
      clipboard: widget.clipboard,
      generator: _generator,
      biometric: widget.biometric,
      backupFiles: widget.backupFiles,
      externalUi: _externalUi,
      pending: _pending,
      terms: widget.terms,
      qrBackup: _qrBackup,
      qrScanner: widget._qrScanner ?? CameraQrScanner.new,
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'Cassaforte',
        debugShowCheckedModeBanner: false,
        theme: theme(Brightness.light),
        darkTheme: theme(Brightness.dark),
        locale: const Locale('es'),
        supportedLocales: const [Locale('es')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => widget.session.registerActivity(),
          child: _LockLayer(child: child!),
        ),
        home: const _Home(),
      ),
    );
  }
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    final status = AppScope.of(context).session.status;
    return switch (status) {
      VaultStatus.initializing => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      VaultStatus.needsSetup => const SetupScreen(),
      // Bloqueada: la lista queda debajo de la pantalla de bloqueo.
      VaultStatus.locked || VaultStatus.unlocked => const VaultScreen(),
    };
  }
}

/// Con la bóveda bloqueada, oculta toda la navegación (sin pintarla, sin
/// foco, sin semántica y sin animaciones) y muestra la pantalla de
/// desbloqueo encima. Así no se pierde lo que se estaba escribiendo.
class _LockLayer extends StatelessWidget {
  const _LockLayer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final locked = AppScope.of(context).session.status == VaultStatus.locked;
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeFocus(
          excluding: locked,
          child: ExcludeSemantics(
            excluding: locked,
            child: TickerMode(
              enabled: !locked,
              child: Offstage(offstage: locked, child: child),
            ),
          ),
        ),
        if (locked)
          // Overlay propio: los campos de texto lo necesitan y la pantalla
          // de bloqueo está fuera del Navigator.
          Overlay(
            initialEntries: [
              OverlayEntry(builder: (_) => const UnlockScreen()),
            ],
          ),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../security/biometric_unlock.dart';
import '../security/clipboard_guard.dart';
import '../security/password_generator.dart';
import '../session/vault_session.dart';
import '../storage/backup_files.dart';
import 'app_scope.dart';
import 'external_ui_guard.dart';
import 'screens/setup_screen.dart';
import 'screens/unlock_screen.dart';
import 'screens/vault_screen.dart';

class CassaforteApp extends StatefulWidget {
  const CassaforteApp({
    super.key,
    required this.session,
    required this.clipboard,
    required this.biometric,
    this.backupFiles = const MethodChannelBackupFiles(),
    PasswordGenerator? generator,
  }) : _generator = generator;

  final VaultSession session;
  final ClipboardGuard clipboard;
  final BiometricUnlock biometric;
  final BackupFiles backupFiles;
  final PasswordGenerator? _generator;

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
    if (_lastStatus == VaultStatus.unlocked && status != VaultStatus.unlocked) {
      // Cierra cualquier pantalla, diálogo u hoja abierta sobre la bóveda.
      _navigatorKey.currentState?.popUntil((route) => route.isFirst);
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
          child: child,
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
      VaultStatus.locked => const UnlockScreen(),
      VaultStatus.unlocked => const VaultScreen(),
    };
  }
}

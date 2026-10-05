import 'dart:convert';
import 'dart:typed_data';

import 'package:cassaforte/src/crypto/kdf.dart';
import 'package:cassaforte/src/crypto/vault_cipher.dart';
import 'package:cassaforte/src/model/vault_entry.dart';
import 'package:cassaforte/src/security/biometric_unlock.dart';
import 'package:cassaforte/src/security/clipboard_guard.dart';
import 'package:cassaforte/src/session/vault_session.dart';
import 'package:cassaforte/src/ui/cassaforte_app.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Derivación rápida SOLO para las pruebas de interfaz (las pruebas de
/// cifrado usan Argon2id real).
class FakeKdf implements KeyDerivation {
  @override
  Future<Uint8List> deriveKey(String password, KdfParams params) async {
    final hash = await Sha256().hash([
      ...params.salt,
      ...utf8.encode(password),
    ]);
    return Uint8List.fromList(hash.bytes);
  }
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

void main() {
  testWidgets('flujo completo: crear, añadir, ver, bloquear, eliminar', (
    tester,
  ) async {
    final store = MemoryVaultStore();
    final session = VaultSession(
      store: store,
      cipher: VaultCipher(keyDerivation: FakeKdf()),
      newKdfParams: fastKdfParams,
    );
    final clipboard = ClipboardGuard(clipboard: FakeClipboard());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      CassaforteApp(
        session: session,
        clipboard: clipboard,
        biometric: BiometricUnlock(
          store: MemoryVaultStore(),
          platform: FakeBiometricPlatform()
            ..status = BiometricAvailability.unsupported,
        ),
        backupFiles: FakeBackupFiles(),
      ),
    );
    await session.initialize();
    await tester.pumpAndSettle();

    // Configuración con aviso de recuperación.
    expect(find.text('Bienvenido a Cassaforte'), findsOneWidget);
    expect(find.textContaining('no habrá forma de recuperar'), findsOneWidget);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'contraseña maestra 1');
    await tester.enterText(fields.at(1), 'contraseña maestra 2');
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Crear bóveda'));
    await tester.pumpAndSettle();
    expect(find.text('Las contraseñas no coinciden.'), findsOneWidget);

    await tester.enterText(fields.at(1), 'contraseña maestra 1');
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Crear bóveda'));
    await tester.pumpAndSettle();
    expect(
      find.text('Debes confirmar que has leído el aviso.'),
      findsOneWidget,
    );
    expect(store.bytes, isNull);

    await tapVisible(tester, find.byType(Checkbox));
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Crear bóveda'));
    await tester.pumpAndSettle();
    expect(session.status, VaultStatus.unlocked);
    expect(find.textContaining('Aún no hay cuentas'), findsOneWidget);

    // Añadir una cuenta.
    await tapVisible(tester, find.text('Añadir'));
    await tester.pumpAndSettle();
    final form = find.byType(TextFormField);
    await tester.enterText(form.at(0), 'Correo');
    await tester.enterText(form.at(1), 'https://correo.example');
    await tester.enterText(form.at(2), 'yo@example.com');
    await tester.enterText(form.at(3), 'S3creta!');
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Correo'), findsOneWidget);
    expect(session.entries, hasLength(1));

    // Búsqueda.
    await tester.enterText(find.byType(SearchBar), 'banco');
    await tester.pump();
    expect(find.text('Correo'), findsNothing);
    await tester.enterText(find.byType(SearchBar), 'CORR');
    await tester.pump();
    expect(find.text('Correo'), findsOneWidget);

    // Detalle: contraseña oculta por defecto.
    await tapVisible(tester, find.text('Correo'));
    await tester.pumpAndSettle();
    expect(find.text('S3creta!'), findsNothing);
    await tester.tap(find.byTooltip('Mostrar contraseña'));
    await tester.pump();
    expect(find.text('S3creta!'), findsOneWidget);

    // Pasar a segundo plano bloquea y cierra el detalle.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pumpAndSettle();
    expect(session.status, VaultStatus.locked);
    expect(find.text('La bóveda está bloqueada.'), findsOneWidget);
    expect(find.text('S3creta!'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    // Contraseña incorrecta.
    await tester.enterText(find.byType(TextFormField), 'no es esta');
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Desbloquear'));
    await tester.pumpAndSettle();
    expect(
      find.text('Contraseña incorrecta o archivo alterado.'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextFormField), 'contraseña maestra 1');
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Desbloquear'));
    await tester.pumpAndSettle();
    expect(find.text('Correo'), findsOneWidget);

    // Eliminar pide confirmación.
    await tapVisible(tester, find.text('Correo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Eliminar'));
    await tester.pumpAndSettle();
    expect(find.text('¿Eliminar cuenta?'), findsOneWidget);
    await tapVisible(tester, find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(session.entries, hasLength(1));

    await tester.tap(find.byTooltip('Eliminar'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Eliminar'));
    await tester.pumpAndSettle();
    expect(session.entries, isEmpty);
    expect(find.textContaining('Aún no hay cuentas'), findsOneWidget);

    session.lock();
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('el generador entrega una contraseña al formulario', (
    tester,
  ) async {
    final store = MemoryVaultStore();
    final session = VaultSession(
      store: store,
      cipher: VaultCipher(keyDerivation: FakeKdf()),
      newKdfParams: fastKdfParams,
    );
    await tester.pumpWidget(
      CassaforteApp(
        session: session,
        clipboard: ClipboardGuard(clipboard: FakeClipboard()),
        biometric: BiometricUnlock(
          store: MemoryVaultStore(),
          platform: FakeBiometricPlatform()
            ..status = BiometricAvailability.unsupported,
        ),
        backupFiles: FakeBackupFiles(),
      ),
    );
    await session.initialize();
    await session.create('contraseña maestra 1');
    await tester.pumpAndSettle();

    await tapVisible(tester, find.text('Añadir'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Generar contraseña'));
    await tester.pumpAndSettle();
    expect(find.text('Generador de contraseñas'), findsOneWidget);
    await tapVisible(tester, find.text('Usar esta contraseña'));
    await tester.pumpAndSettle();

    final passwordField = tester.widget<EditableText>(
      find.descendant(
        of: find.byType(TextFormField).at(3),
        matching: find.byType(EditableText),
      ),
    );
    expect(passwordField.controller.text, hasLength(20));

    session.lock();
    await tester.pumpAndSettle();
  });

  testWidgets('restaurar una copia al empezar y exportarla desde Ajustes', (
    tester,
  ) async {
    // Copia hecha en "otro teléfono".
    final source = VaultSession(
      store: MemoryVaultStore(),
      cipher: VaultCipher(keyDerivation: FakeKdf()),
      newKdfParams: fastKdfParams,
    );
    await source.initialize();
    await source.create('contraseña maestra 1');
    await source.saveEntry(VaultEntry.create(title: 'Banco', password: 'x1'));
    final backup = await source.exportBackup('contraseña maestra 1');
    source.dispose();

    final store = MemoryVaultStore();
    final files = FakeBackupFiles()..toOpen = backup;
    final session = VaultSession(
      store: store,
      cipher: VaultCipher(keyDerivation: FakeKdf()),
      newKdfParams: fastKdfParams,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      CassaforteApp(
        session: session,
        clipboard: ClipboardGuard(clipboard: FakeClipboard()),
        biometric: BiometricUnlock(
          store: MemoryVaultStore(),
          platform: FakeBiometricPlatform()
            ..status = BiometricAvailability.unsupported,
        ),
        backupFiles: files,
      ),
    );
    await session.initialize();
    await tester.pumpAndSettle();

    await tapVisible(tester, find.text('Restaurar copia de seguridad'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextFormField),
      ),
      'contraseña maestra 1',
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(session.status, VaultStatus.unlocked);
    expect(find.text('Banco'), findsOneWidget);

    // Exportar desde Ajustes.
    await tester.tap(find.byTooltip('Ajustes y copias'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exportar copia'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextFormField),
      ),
      'contraseña maestra 1',
    );
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(files.saved, store.bytes);
    expect(session.status, VaultStatus.unlocked);

    session.lock();
    await tester.pump(const Duration(seconds: 5));
  });

  Future<VaultSession> openVaultWith(
    WidgetTester tester,
    FakeBiometricPlatform platform,
  ) async {
    final session = VaultSession(
      store: MemoryVaultStore(),
      cipher: VaultCipher(keyDerivation: FakeKdf()),
      newKdfParams: fastKdfParams,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      CassaforteApp(
        session: session,
        clipboard: ClipboardGuard(clipboard: FakeClipboard()),
        biometric: BiometricUnlock(
          store: MemoryVaultStore(),
          platform: platform,
        ),
        backupFiles: FakeBackupFiles(),
      ),
    );
    await session.initialize();
    await session.create('contraseña maestra 1');
    await tester.pumpAndSettle();
    return session;
  }

  testWidgets('activar la huella desde Ajustes y desbloquear con ella', (
    tester,
  ) async {
    final platform = FakeBiometricPlatform();
    final session = await openVaultWith(tester, platform);

    await tester.tap(find.byTooltip('Ajustes y copias'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Comprobando'), findsNothing);
    final toggle = find.byType(SwitchListTile);
    expect(tester.widget<SwitchListTile>(toggle).onChanged, isNotNull);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    expect(platform.prompts, 1);

    // Al bloquear, la pantalla de desbloqueo muestra la huella sola.
    session.lock();
    await tester.pumpAndSettle();
    expect(session.status, VaultStatus.unlocked);
    expect(platform.prompts, 2);

    // Si se cancela, queda el botón para intentarlo de nuevo.
    platform.cancelNext = true;
    session.lock();
    await tester.pumpAndSettle();
    expect(session.status, VaultStatus.locked);
    await tester.tap(find.text('Usar huella o patrón'));
    await tester.pumpAndSettle();
    expect(session.status, VaultStatus.unlocked);

    // Al terminar, se bloquea sin volver a abrir.
    platform.cancelNext = true;
    session.lock();
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('si el sistema falla al comprobar la huella, no se queda '
      'en «Comprobando»', (tester) async {
    final platform = FakeBiometricPlatform()..failStatus = true;
    final session = await openVaultWith(tester, platform);

    await tester.tap(find.byTooltip('Ajustes y copias'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Comprobando'), findsNothing);
    expect(
      find.text('No se pudo comprobar la huella en este teléfono.'),
      findsOneWidget,
    );
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );

    session.lock();
    await tester.pump(const Duration(seconds: 5));
  });
}

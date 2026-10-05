import 'dart:convert';
import 'dart:typed_data';

import 'package:cassaforte/src/crypto/kdf.dart';
import 'package:cassaforte/src/crypto/vault_cipher.dart';
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
      CassaforteApp(session: session, clipboard: clipboard),
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
}

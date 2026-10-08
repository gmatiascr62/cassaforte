import 'dart:convert';
import 'dart:typed_data';

import 'package:cassaforte/src/backup/backup_pdf.dart';
import 'package:cassaforte/src/backup/qr_backup_service.dart';
import 'package:cassaforte/src/backup/qr_chunks.dart';
import 'package:cassaforte/src/backup/qr_image_reader.dart';
import 'package:cassaforte/src/crypto/vault_cipher.dart';
import 'package:cassaforte/src/legal/terms.dart';
import 'package:cassaforte/src/model/vault_entry.dart';
import 'package:cassaforte/src/security/biometric_unlock.dart';
import 'package:cassaforte/src/security/clipboard_guard.dart';
import 'package:cassaforte/src/session/vault_session.dart';
import 'package:cassaforte/src/storage/vault_store.dart';
import 'package:cassaforte/src/ui/cassaforte_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'backup_page_renderer.dart';
import 'helpers.dart';

const master = 'contraseña maestra 1';

class Phone {
  Phone(this.tester, {MemoryVaultStore? store, bool termsAccepted = true})
    : store = store ?? MemoryVaultStore(),
      termsAccepted = termsAccepted;

  final WidgetTester tester;
  final MemoryVaultStore store;
  final bool termsAccepted;
  final files = FakeBackupFiles();
  final raster = FakeRasterizer();
  final scanner = FakeQrScanner();
  late final backup = TestQrBackupService(kdf: FakeKdf(), raster: raster);
  late final session = VaultSession(
    store: store,
    cipher: VaultCipher(keyDerivation: FakeKdf()),
    newKdfParams: fastKdfParams,
  );

  Future<void> open() async {
    final terms = TermsAcceptance(MemoryVaultStore());
    if (termsAccepted) await terms.accept();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      CassaforteApp(
        key: UniqueKey(),
        session: session,
        clipboard: ClipboardGuard(clipboard: FakeClipboard()),
        biometric: BiometricUnlock(
          store: MemoryVaultStore(),
          platform: FakeBiometricPlatform()
            ..status = BiometricAvailability.unsupported,
        ),
        backupFiles: files,
        terms: terms,
        qrBackup: backup,
        qrScanner: () => scanner,
      ),
    );
    await session.initialize();
    await tester.pumpAndSettle();
  }

  Future<void> close() async {
    session.lock();
    await tester.pump(const Duration(seconds: 5));
  }
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> typePassword(WidgetTester tester, String password) async {
  await tester.enterText(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextFormField),
    ),
    password,
  );
}

List<VaultEntry> accounts(int n) => [
  for (var i = 0; i < n; i++)
    VaultEntry.create(
      title: 'Cuenta $i',
      url: 'https://sitio$i.example',
      username: 'usuario$i',
      password: 'Clave-$i-${'x' * (i % 7)}',
      notes: i.isEven ? 'nota $i' : '',
      fields: [CustomField(label: 'PIN', value: '${1000 + i}', hidden: true)],
    ),
];

/// Teléfono con una bóveda abierta con [entries].
Future<Phone> phoneWithVault(
  WidgetTester tester,
  List<VaultEntry> entries,
) async {
  final phone = Phone(tester);
  await phone.session.initialize();
  await phone.session.create(master);
  for (final e in entries) {
    await phone.session.saveEntry(e);
  }
  await phone.open();
  return phone;
}

/// Exporta desde Ajustes y devuelve el PDF guardado.
Future<Uint8List> exportFromSettings(WidgetTester tester, Phone phone) async {
  await tap(tester, find.byTooltip('Ajustes y copias'));
  await tap(tester, find.text('Exportar copia de seguridad'));
  expect(find.textContaining('Guardalo fuera del teléfono'), findsOneWidget);
  await tap(tester, find.text('Continuar'));
  await typePassword(tester, master);
  await tap(tester, find.text('Crear copia'));
  expect(find.text('Copia lista'), findsOneWidget);
  await tap(tester, find.text('Guardar PDF'));
  expect(phone.files.savedMime, 'application/pdf');
  expect(find.text('PDF guardado.'), findsOneWidget);
  return phone.files.saved!;
}

void main() {
  testWidgets(
    'exportar a PDF en un teléfono y recuperar en otro desde el PDF',
    (tester) async {
      final original = accounts(25);
      final phone1 = await phoneWithVault(tester, original);
      final pdf = await exportFromSettings(tester, phone1);
      expect(QrBackupService.looksLikePdf(pdf), isTrue);
      final codes = phone1.backup.last!.codeTexts;

      // Imprimir y compartir usan las funciones de Android.
      await tap(tester, find.text('Imprimir'));
      expect(phone1.files.printed, pdf);
      await tap(tester, find.text('Compartir'));
      expect(phone1.files.shared, pdf);
      await phone1.close();

      // Teléfono nuevo, sin bóveda.
      final phone2 = Phone(tester, termsAccepted: false);
      phone2.files.toOpen = pdf;
      phone2.raster.pages = renderPages(codes);
      await phone2.open();
      await tap(tester, find.byType(Checkbox)); // términos
      await tap(tester, find.text('Recuperar mis contraseñas'));
      expect(find.text('Escanear códigos QR'), findsOneWidget);
      await tap(tester, find.text('Seleccionar archivo PDF'));

      // Contraseña incorrecta: no se crea nada y se puede reintentar.
      await typePassword(tester, 'no es esta');
      await tap(tester, find.text('Recuperar'));
      expect(find.textContaining('Contraseña incorrecta'), findsOneWidget);
      expect(phone2.store.bytes, isNull);
      expect(phone2.session.status, VaultStatus.needsSetup);

      await typePassword(tester, master);
      await tap(tester, find.text('Recuperar'));
      expect(phone2.session.status, VaultStatus.unlocked);
      expect(find.text('Restauración completada'), findsOneWidget);
      expect(find.textContaining('Se recuperaron 25 cuenta'), findsOneWidget);
      await tap(tester, find.text('Aceptar'));

      final restored = {for (final e in phone2.session.entries) e.id: e};
      expect(restored.length, 25);
      for (final e in original) {
        final r = restored[e.id]!;
        expect(
          [r.title, r.url, r.username, r.password, r.notes, r.fields],
          [e.title, e.url, e.username, e.password, e.notes, e.fields],
        );
      }
      // La bóveda nueva se abre con la contraseña de la copia.
      phone2.session.lock();
      await phone2.session.unlock(master);
      expect(phone2.session.entries, hasLength(25));
      await phone2.close();
    },
  );

  testWidgets('recuperar escaneando con la cámara, en cualquier orden', (
    tester,
  ) async {
    final original = accounts(40);
    final phone1 = await phoneWithVault(tester, original);
    await exportFromSettings(tester, phone1);
    final codes = phone1.backup.last!.codeTexts;
    expect(codes.length, greaterThan(2));
    await phone1.close();

    // Códigos de otra copia distinta.
    final other = QrChunk.split(
      await phone1.backup.cipher.seal(accounts(3), master),
    );

    final phone2 = Phone(tester);
    await phone2.open();
    await tap(tester, find.byType(Checkbox));
    await tap(tester, find.text('Recuperar mis contraseñas'));
    await tap(tester, find.text('Escanear códigos QR'));
    expect(phone2.scanner.started, isTrue);
    expect(find.text('Escaneá cualquier código de la copia'), findsOneWidget);

    final order = [...codes.reversed];
    phone2.scanner.show(order.first);
    await tester.pump();
    expect(
      find.text('1 de ${codes.length} códigos escaneados'),
      findsOneWidget,
    );

    phone2.scanner.show(order.first); // repetido
    await tester.pump();
    expect(find.text('Ese código ya estaba leído.'), findsOneWidget);

    phone2.scanner.show(other.first); // de otra copia
    await tester.pump();
    expect(find.textContaining('es de otra copia'), findsOneWidget);

    phone2.scanner.show('https://ejemplo.com'); // ajeno
    await tester.pump();
    expect(
      find.textContaining('No es un código de Cassaforte'),
      findsOneWidget,
    );
    expect(
      find.text('1 de ${codes.length} códigos escaneados'),
      findsOneWidget,
    );

    for (final c in order.skip(1)) {
      phone2.scanner.show(c);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    // Completo: se cierra la cámara y se pide la contraseña.
    expect(phone2.scanner.started, isFalse);
    await typePassword(tester, master);
    await tap(tester, find.text('Recuperar'));
    expect(phone2.session.status, VaultStatus.unlocked);
    expect(phone2.session.entries, hasLength(40));
    await tap(tester, find.text('Aceptar'));
    await phone2.close();
  });

  testWidgets('sin permiso de cámara se explica y se puede usar el PDF', (
    tester,
  ) async {
    final phone = Phone(tester);
    phone.scanner.failWith = 'Cassaforte no tiene permiso para usar la cámara.';
    await phone.open();
    await tap(tester, find.byType(Checkbox));
    await tap(tester, find.text('Recuperar mis contraseñas'));
    await tap(tester, find.text('Escanear códigos QR'));
    expect(find.textContaining('no tiene permiso'), findsOneWidget);
    expect(phone.store.bytes, isNull);
    await phone.close();
  });

  testWidgets('archivos inválidos no crean ni modifican nada', (tester) async {
    final phone = Phone(tester);
    await phone.open();
    await tap(tester, find.byType(Checkbox));
    await tap(tester, find.text('Recuperar mis contraseñas'));

    // No es PDF ni copia anterior.
    phone.files.toOpen = Uint8List.fromList(utf8.encode('hola mundo'));
    await tap(tester, find.text('Seleccionar archivo PDF'));
    expect(find.textContaining('no es un PDF ni una copia'), findsOneWidget);

    // PDF dañado (el renderizador falla).
    phone.files.toOpen = Uint8List.fromList(utf8.encode('%PDF-1.7 roto'));
    phone.raster.fail = true;
    await tap(tester, find.text('Seleccionar archivo PDF'));
    expect(find.text('No se pudo leer el PDF'), findsOneWidget);

    // PDF válido pero sin códigos de Cassaforte.
    phone.raster
      ..fail = false
      ..pages = [_blankPage()];
    await tap(tester, find.text('Seleccionar archivo PDF'));
    expect(
      find.text('El PDF no contiene códigos de una copia de Cassaforte'),
      findsOneWidget,
    );

    // PDF con códigos faltantes: avisa y no pide contraseña.
    final codes = QrChunk.split(
      await phone.backup.cipher.seal(accounts(40), master),
    );
    expect(codes.length, greaterThan(1));
    phone.raster.pages = renderPages(codes.sublist(0, codes.length - 1));
    await tap(tester, find.text('Seleccionar archivo PDF'));
    expect(find.textContaining('Faltan 1 códigos'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);

    expect(phone.store.bytes, isNull);
    expect(phone.session.status, VaultStatus.needsSetup);
    await phone.close();
  });

  testWidgets('importar un PDF dentro de la bóveda fusiona sin cambiar la '
      'contraseña maestra', (tester) async {
    final phone1 = await phoneWithVault(tester, accounts(5));
    final pdf = await exportFromSettings(tester, phone1);
    final codes = phone1.backup.last!.codeTexts;
    await phone1.close();

    final mine = VaultEntry.create(title: 'Solo mía', password: 'p');
    final phone2 = await phoneWithVault(tester, [mine]);
    phone2.files.toOpen = pdf;
    phone2.raster.pages = renderPages(codes);
    await tap(tester, find.byTooltip('Ajustes y copias'));
    await tap(tester, find.text('Importar copia de seguridad'));
    await tap(tester, find.text('Seleccionar archivo PDF'));
    await typePassword(tester, master);
    await tap(tester, find.text('Recuperar'));
    await tap(tester, find.text('Fusionar'));
    expect(phone2.session.entries, hasLength(6));
    expect(find.textContaining('Importadas 5 nueva(s)'), findsOneWidget);
    await phone2.close();
  });

  group('PDF', () {
    test('contiene solo códigos cifrados y numeración', () async {
      final entries = accounts(30);
      final cipher = TestQrBackupService(
        kdf: FakeKdf(),
        raster: FakeRasterizer(),
      ).cipher;
      final payload = await cipher.seal(entries, master);
      final codes = QrChunk.split(payload);
      final pdf = await buildBackupPdf(
        codes: codes,
        copyId: QrChunk.hexId(QrChunk.copyIdOf(payload)),
        compress: false,
      );
      final text = latin1.decode(pdf);
      expect(text.startsWith('%PDF-'), isTrue);
      expect(
        RegExp(r'/Type\s*/Page\b').allMatches(text).length,
        (codes.length + 5) ~/ 6,
      );
      for (final e in entries) {
        for (final secret in [e.title, e.username, e.password, e.url, 'PIN']) {
          expect(text.contains(secret), isFalse, reason: secret);
        }
      }
    });
  });

  group('Sesión: restauración atómica', () {
    test('crea la bóveda con la contraseña de la copia', () async {
      final store = MemoryVaultStore();
      final session = VaultSession(
        store: store,
        cipher: VaultCipher(keyDerivation: FakeKdf()),
        newKdfParams: fastKdfParams,
      );
      await session.initialize();
      final entries = accounts(10);
      await session.restoreEntries(entries, master);
      expect(session.status, VaultStatus.unlocked);
      expect(store.writes, 1);
      session.lock();
      await expectLater(
        session.unlock('otra'),
        throwsA(isA<WrongPasswordException>()),
      );
      await session.unlock(master);
      expect(session.entries, hasLength(10));
    });

    test('si la escritura falla no queda ninguna bóveda', () async {
      final store = MemoryVaultStore()..failWrites = true;
      final session = VaultSession(
        store: store,
        cipher: VaultCipher(keyDerivation: FakeKdf()),
        newKdfParams: fastKdfParams,
      );
      await session.initialize();
      await expectLater(
        session.restoreEntries(accounts(3), master),
        throwsA(isA<StateError>()),
      );
      expect(store.bytes, isNull);
      expect(session.status, VaultStatus.needsSetup);
      expect(session.entries, isEmpty);
    });

    test('nunca sobrescribe una bóveda existente', () async {
      final store = MemoryVaultStore();
      final first = VaultSession(
        store: store,
        cipher: VaultCipher(keyDerivation: FakeKdf()),
        newKdfParams: fastKdfParams,
      );
      await first.initialize();
      await first.create('la contraseña de siempre');
      final before = Uint8List.fromList(store.bytes!);

      final tricked = VaultSession(
        store: _HideOnce(store),
        cipher: VaultCipher(keyDerivation: FakeKdf()),
        newKdfParams: fastKdfParams,
      );
      await tricked.initialize();
      await expectLater(
        tricked.restoreEntries(accounts(3), master),
        throwsA(isA<VaultAlreadyExistsException>()),
      );
      expect(store.bytes, before);
    });
  });
}

GrayImage _blankPage() =>
    GrayImage(400, 600, Uint8List(400 * 600)..fillRange(0, 400 * 600, 255));

class _HideOnce implements VaultStore {
  _HideOnce(this.inner);
  final VaultStore inner;
  bool _hidden = true;

  @override
  Future<bool> exists() async {
    if (_hidden) {
      _hidden = false;
      return false;
    }
    return inner.exists();
  }

  @override
  Future<Uint8List> read() => inner.read();

  @override
  Future<void> writeAtomic(Uint8List bytes) => inner.writeAtomic(bytes);

  @override
  Future<void> delete() => inner.delete();
}

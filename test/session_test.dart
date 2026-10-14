import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cassaforte/src/crypto/vault_cipher.dart';
import 'package:cassaforte/src/model/vault_entry.dart';
import 'package:cassaforte/src/session/vault_session.dart';
import 'package:cassaforte/src/storage/vault_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const master = 'mi contraseña maestra';

VaultSession newSession(
  VaultStore store, {
  ControlledKdf? kdf,
  Duration autoLock = const Duration(minutes: 5),
}) {
  return VaultSession(
    store: store,
    cipher: VaultCipher(keyDerivation: kdf ?? ControlledKdf()),
    newKdfParams: fastKdfParams,
    autoLockAfter: autoLock,
  );
}

VaultEntry sampleEntry([String title = 'Correo']) => VaultEntry.create(
  title: title,
  url: 'https://correo.example',
  username: 'yo@example.com',
  password: 'S3creta!',
  notes: 'nota privada',
);

void main() {
  group('Creación y persistencia', () {
    late Directory dir;
    late FileVaultStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('cassaforte_session_');
      store = FileVaultStore('${dir.path}/${FileVaultStore.fileName}');
    });

    tearDown(() async => dir.delete(recursive: true));

    test('crea, guarda y vuelve a abrir la bóveda desde disco', () async {
      final session = newSession(store);
      await session.initialize();
      expect(session.status, VaultStatus.needsSetup);
      await session.create(master);
      expect(session.status, VaultStatus.unlocked);

      final entry = sampleEntry();
      await session.saveEntry(entry);
      await session.saveEntry(sampleEntry('Banco'));
      await session.saveEntry(entry.copyWith(password: 'nueva'));
      expect(session.entries.map((e) => e.title), ['Banco', 'Correo']);
      session.dispose();

      // El archivo no contiene ningún dato en claro.
      final raw = utf8.decode(await File(store.path).readAsBytes());
      for (final secret in [
        'Correo',
        'Banco',
        'correo.example',
        'yo@example.com',
        'nueva',
        'nota privada',
        master,
      ]) {
        expect(raw, isNot(contains(secret)));
      }

      final reopened = newSession(store);
      await reopened.initialize();
      expect(reopened.status, VaultStatus.locked);
      await reopened.unlock(master);
      expect(reopened.entries, hasLength(2));
      final loaded = reopened.entryById(entry.id)!;
      expect(loaded.title, 'Correo');
      expect(loaded.url, 'https://correo.example');
      expect(loaded.username, 'yo@example.com');
      expect(loaded.password, 'nueva');
      expect(loaded.notes, 'nota privada');

      await reopened.deleteEntry(entry.id);
      reopened.lock();
      await reopened.unlock(master);
      expect(reopened.entries.map((e) => e.title), ['Banco']);
      reopened.dispose();
    });

    test('no crea una bóveda encima de una existente', () async {
      final first = newSession(store);
      await first.initialize();
      await first.create(master);
      await first.saveEntry(sampleEntry());
      final before = await File(store.path).readAsBytes();

      // Una sesión que, por error, creyera que no hay bóveda no la
      // sobrescribe: create() vuelve a comprobarlo antes de escribir.
      final tricked = newSession(_HideOnceStore(store));
      await tricked.initialize();
      expect(tricked.status, VaultStatus.needsSetup);
      await expectLater(
        tricked.create('otra contraseña maestra'),
        throwsA(isA<VaultAlreadyExistsException>()),
      );
      expect(await File(store.path).readAsBytes(), before);
      expect(tricked.status, VaultStatus.locked);
    });

    test('exige una contraseña maestra mínima', () async {
      final session = newSession(store);
      await session.initialize();
      expect(() => session.create('corta'), throwsArgumentError);
      expect(await store.exists(), isFalse);
    });
  });

  group('Contraseña incorrecta y archivos alterados', () {
    late MemoryVaultStore store;

    setUp(() async {
      store = MemoryVaultStore();
      final session = newSession(store);
      await session.initialize();
      await session.create(master);
      await session.saveEntry(sampleEntry());
      session.dispose();
    });

    test('rechaza una contraseña incorrecta sin escribir nada', () async {
      final before = Uint8List.fromList(store.bytes!);
      final writes = store.writes;
      final session = newSession(store);
      await session.initialize();
      await expectLater(
        session.unlock('contraseña equivocada'),
        throwsA(isA<WrongPasswordException>()),
      );
      expect(session.status, VaultStatus.locked);
      expect(session.entries, isEmpty);
      expect(store.writes, writes);
      expect(store.bytes, before);
      // Después, la correcta sigue funcionando.
      await session.unlock(master);
      expect(session.entries, hasLength(1));
    });

    test('rechaza un archivo con el contenido cifrado alterado', () async {
      final doc = jsonDecode(utf8.decode(store.bytes!)) as Map<String, dynamic>;
      final data = base64.decode(doc['ciphertext'] as String);
      data[data.length ~/ 2] ^= 0x01;
      doc['ciphertext'] = base64.encode(data);
      store.bytes = Uint8List.fromList(utf8.encode(jsonEncode(doc)));
      final tampered = Uint8List.fromList(store.bytes!);
      final writes = store.writes;

      final session = newSession(store);
      await session.initialize();
      await expectLater(
        session.unlock(master),
        throwsA(isA<WrongPasswordException>()),
      );
      expect(session.status, VaultStatus.locked);
      expect(store.writes, writes);
      expect(store.bytes, tampered);
    });

    test('rechaza un archivo dañado sin sobrescribirlo', () async {
      store.bytes = Uint8List.fromList(store.bytes!.sublist(0, 40));
      final damaged = Uint8List.fromList(store.bytes!);
      final session = newSession(store);
      await session.initialize();
      expect(session.status, VaultStatus.locked);
      await expectLater(
        session.unlock(master),
        throwsA(isA<VaultCorruptedException>()),
      );
      expect(store.bytes, damaged);
    });

    test(
      'si falla el guardado, la sesión conserva el estado anterior',
      () async {
        final session = newSession(store);
        await session.initialize();
        await session.unlock(master);
        final before = Uint8List.fromList(store.bytes!);
        store.failWrites = true;
        await expectLater(
          session.saveEntry(sampleEntry('Nueva')),
          throwsA(isA<StateError>()),
        );
        expect(session.entries, hasLength(1));
        expect(store.bytes, before);
        store.failWrites = false;
        await session.saveEntry(sampleEntry('Nueva'));
        expect(session.entries, hasLength(2));
      },
    );
  });

  group('Bloqueo de sesión', () {
    late MemoryVaultStore store;
    late ControlledKdf kdf;

    setUp(() async {
      store = MemoryVaultStore();
      kdf = ControlledKdf();
      final session = newSession(store, kdf: kdf);
      await session.initialize();
      await session.create(master);
      await session.saveEntry(sampleEntry());
      session.dispose();
    });

    test('lock borra las cuentas de la memoria de la sesión', () async {
      final session = newSession(store, kdf: kdf);
      await session.initialize();
      await session.unlock(master);
      expect(session.entries, isNotEmpty);
      session.lock();
      expect(session.status, VaultStatus.locked);
      expect(session.entries, isEmpty);
      expect(session.entryById('x'), isNull);
      await expectLater(
        session.saveEntry(sampleEntry()),
        throwsA(isA<VaultLockedException>()),
      );
    });

    test('un desbloqueo pendiente no reabre una sesión bloqueada', () async {
      final session = newSession(store, kdf: kdf);
      await session.initialize();
      kdf.hold();
      final pending = session.unlock(master);
      await Future<void>.delayed(Duration.zero);
      expect(session.isBusy, isTrue);

      session.lock(); // p. ej., la aplicación pasa a segundo plano
      expect(session.isBusy, isFalse);
      kdf.release();

      await expectLater(pending, throwsA(isA<VaultLockedException>()));
      expect(session.status, VaultStatus.locked);
      expect(session.entries, isEmpty);

      // Un desbloqueo nuevo funciona con normalidad.
      kdf.gate = null;
      await session.unlock(master);
      expect(session.status, VaultStatus.unlocked);
    });

    test('un guardado pendiente no reabre una sesión bloqueada', () async {
      final session = newSession(store, kdf: kdf);
      await session.initialize();
      await session.unlock(master);

      // Una petición hecha con la sesión ya bloqueada se rechaza.
      session.lock();
      await expectLater(
        session.saveEntry(sampleEntry('Rechazada')),
        throwsA(isA<VaultLockedException>()),
      );
      await session.unlock(master);

      // Bloqueo mientras se está escribiendo en disco.
      store
        ..writeGate = Completer<void>()
        ..writeStarted = Completer<void>();
      final pending = session.saveEntry(sampleEntry('Pendiente'));
      await store.writeStarted!.future;
      session.lock();
      store.writeGate!.complete();
      await expectLater(pending, throwsA(isA<VaultLockedException>()));
      expect(session.status, VaultStatus.locked);
      expect(session.entries, isEmpty);
      store
        ..writeGate = null
        ..writeStarted = null;

      // El cambio se guardó completo y cifrado.
      await session.unlock(master);
      final titles = session.entries.map((e) => e.title);
      expect(titles, contains('Pendiente'));
      expect(titles, isNot(contains('Rechazada')));
    });

    test('una creación pendiente no abre la sesión si se bloquea', () async {
      final emptyStore = MemoryVaultStore();
      final session = newSession(emptyStore, kdf: kdf);
      await session.initialize();
      kdf.hold();
      final pending = session.create(master);
      await Future<void>.delayed(Duration.zero);
      session.lock();
      kdf.release();
      await expectLater(pending, throwsA(isA<VaultLockedException>()));
      expect(session.status, VaultStatus.locked);
      kdf.gate = null;
      await session.unlock(master);
      expect(session.status, VaultStatus.unlocked);
    });

    test('los guardados simultáneos no se pisan', () async {
      final session = newSession(store, kdf: kdf);
      await session.initialize();
      await session.unlock(master);
      await Future.wait([
        for (var i = 0; i < 5; i++) session.saveEntry(sampleEntry('Cuenta $i')),
      ]);
      expect(session.entries, hasLength(6));
      session.lock();
      await session.unlock(master);
      expect(session.entries, hasLength(6));
    });

    test('se bloquea tras el periodo de inactividad', () async {
      final session = newSession(
        store,
        kdf: kdf,
        autoLock: const Duration(milliseconds: 300),
      );
      await session.initialize();
      await session.unlock(master);

      // La actividad reinicia el temporizador.
      for (var i = 0; i < 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        session.registerActivity();
        expect(session.status, VaultStatus.unlocked);
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(session.status, VaultStatus.locked);
      expect(session.entries, isEmpty);
    });
  });
}

/// Almacén que oculta la bóveda en la primera comprobación.
class _HideOnceStore implements VaultStore {
  _HideOnceStore(this.inner);
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

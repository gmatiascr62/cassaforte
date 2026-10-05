import 'dart:convert';
import 'dart:typed_data';

import 'package:cassaforte/src/crypto/vault_cipher.dart';
import 'package:cassaforte/src/model/vault_entry.dart';
import 'package:cassaforte/src/session/vault_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const master = 'contraseña maestra larga';

Future<VaultSession> openSession(MemoryVaultStore store, {String? pw}) async {
  final session = VaultSession(
    store: store,
    cipher: VaultCipher(keyDerivation: ControlledKdf()),
    newKdfParams: fastKdfParams,
  );
  await session.initialize();
  if (session.status == VaultStatus.needsSetup) {
    await session.create(pw ?? master);
  } else {
    await session.unlock(pw ?? master);
  }
  return session;
}

VaultEntry entry(String title, {DateTime? at}) => VaultEntry.create(
  title: title,
  username: '$title@example.com',
  password: 'clave-$title',
  now: at,
);

void main() {
  group('Exportar', () {
    test('exige la contraseña maestra y devuelve el archivo cifrado', () async {
      final store = MemoryVaultStore();
      final session = await openSession(store);
      await session.saveEntry(entry('Banco'));

      await expectLater(
        session.exportBackup('no es la maestra'),
        throwsA(isA<WrongPasswordException>()),
      );
      final backup = await session.exportBackup(master);
      expect(backup, store.bytes);
      expect(utf8.decode(backup), isNot(contains('Banco')));
    });

    test('no exporta con la sesión bloqueada', () async {
      final session = await openSession(MemoryVaultStore());
      session.lock();
      await expectLater(
        session.exportBackup(master),
        throwsA(isA<VaultLockedException>()),
      );
    });
  });

  group('Abrir copia', () {
    late Uint8List backup;

    setUp(() async {
      final session = await openSession(MemoryVaultStore());
      await session.saveEntry(entry('Correo'));
      await session.saveEntry(entry('Banco'));
      backup = await session.exportBackup(master);
    });

    test('descifra con la contraseña correcta', () async {
      final other = await openSession(
        MemoryVaultStore(),
        pw: 'otra maestra larga',
      );
      final entries = await other.openBackup(backup, master);
      expect(entries.map((e) => e.title).toSet(), {'Correo', 'Banco'});
    });

    test('rechaza contraseña incorrecta y archivos alterados', () async {
      final other = await openSession(
        MemoryVaultStore(),
        pw: 'otra maestra larga',
      );
      await expectLater(
        other.openBackup(backup, 'equivocada'),
        throwsA(isA<WrongPasswordException>()),
      );
      final doc = jsonDecode(utf8.decode(backup)) as Map<String, dynamic>;
      final data = base64.decode(doc['ciphertext'] as String);
      data[5] ^= 1;
      doc['ciphertext'] = base64.encode(data);
      await expectLater(
        other.openBackup(
          Uint8List.fromList(utf8.encode(jsonEncode(doc))),
          master,
        ),
        throwsA(isA<WrongPasswordException>()),
      );
      await expectLater(
        other.openBackup(Uint8List.fromList(utf8.encode('hola')), master),
        throwsA(isA<VaultCorruptedException>()),
      );
    });

    test(
      'restaura en un teléfono nuevo con la contraseña de la copia',
      () async {
        final store = MemoryVaultStore();
        final fresh = VaultSession(
          store: store,
          cipher: VaultCipher(keyDerivation: ControlledKdf()),
          newKdfParams: fastKdfParams,
        );
        await fresh.initialize();
        await expectLater(
          fresh.restoreBackup(backup, 'equivocada'),
          throwsA(isA<WrongPasswordException>()),
        );
        expect(store.bytes, isNull);
        await fresh.restoreBackup(backup, master);
        expect(fresh.status, VaultStatus.unlocked);
        expect(fresh.entries, hasLength(2));

        // Sigue funcionando: guarda, bloquea y vuelve a abrir.
        await fresh.saveEntry(entry('Nueva'));
        fresh.lock();
        await fresh.unlock(master);
        expect(fresh.entries, hasLength(3));
      },
    );

    test('restaurar no sobrescribe una bóveda existente', () async {
      final store = MemoryVaultStore();
      final existing = await openSession(store, pw: 'otra maestra larga');
      await existing.saveEntry(entry('Mía'));
      final before = Uint8List.fromList(store.bytes!);
      store.bytes = null;
      final fresh = VaultSession(
        store: store,
        cipher: VaultCipher(keyDerivation: ControlledKdf()),
        newKdfParams: fastKdfParams,
      );
      await fresh.initialize();
      store.bytes = before; // aparece una bóveda mientras tanto
      await expectLater(
        fresh.restoreBackup(backup, master),
        throwsA(isA<VaultAlreadyExistsException>()),
      );
      expect(store.bytes, before);
    });
  });

  group('Importar', () {
    test('fusiona sin cambiar la contraseña maestra', () async {
      final source = await openSession(
        MemoryVaultStore(),
        pw: 'maestra de la copia',
      );
      await source.saveEntry(entry('Correo'));
      await source.saveEntry(entry('Banco'));
      final backup = await source.exportBackup('maestra de la copia');

      final store = MemoryVaultStore();
      final target = await openSession(store);
      await target.saveEntry(entry('Mía'));
      final incoming = await target.openBackup(backup, 'maestra de la copia');
      final result = await target.importEntries(incoming, replace: false);
      expect(result.added, 2);
      expect(target.entries.map((e) => e.title), ['Banco', 'Correo', 'Mía']);

      target.lock();
      await target.unlock(master);
      expect(target.entries, hasLength(3));
    });

    test('reemplazar deja solo las cuentas de la copia', () async {
      final target = await openSession(MemoryVaultStore());
      await target.saveEntry(entry('Mía'));
      await target.importEntries([entry('Copia')], replace: true);
      expect(target.entries.map((e) => e.title), ['Copia']);
    });

    test('mergeEntries conserva la versión más reciente', () {
      final old = DateTime.utc(2024);
      final recent = DateTime.utc(2025);
      final a = entry('A', at: old);
      final b = entry('B', at: recent);
      final aNew = a.copyWith(password: 'nueva', updatedAt: recent);
      final bOld = b.copyWith(password: 'vieja', updatedAt: old);
      final c = entry('C');

      final result = mergeEntries([a, b], [aNew, bOld, c]);
      final byId = {for (final e in result.entries) e.id: e};
      expect(result.added, 1);
      expect(result.updated, 1);
      expect(byId[a.id]!.password, 'nueva');
      expect(byId[b.id]!.password, 'clave-B');
      expect(byId.containsKey(c.id), isTrue);
    });
  });
}

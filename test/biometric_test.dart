import 'package:cassaforte/src/crypto/vault_cipher.dart';
import 'package:cassaforte/src/model/vault_entry.dart';
import 'package:cassaforte/src/security/biometric_unlock.dart';
import 'package:cassaforte/src/session/vault_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const master = 'contraseña maestra larga';

void main() {
  late MemoryVaultStore vaultStore;
  late MemoryVaultStore keyStore;
  late FakeBiometricPlatform platform;
  late BiometricUnlock biometric;
  late VaultSession session;

  setUp(() async {
    vaultStore = MemoryVaultStore();
    keyStore = MemoryVaultStore();
    platform = FakeBiometricPlatform();
    biometric = BiometricUnlock(store: keyStore, platform: platform);
    session = VaultSession(
      store: vaultStore,
      cipher: VaultCipher(keyDerivation: ControlledKdf()),
      newKdfParams: fastKdfParams,
    );
    await session.initialize();
    await session.create(master);
    await session.saveEntry(
      VaultEntry.create(title: 'Banco', password: 'secreta'),
    );
  });

  test('activa la huella y desbloquea sin la contraseña maestra', () async {
    expect(await biometric.isEnabled(), isFalse);
    await biometric.enable(session);
    expect(await biometric.isEnabled(), isTrue);
    // La clave guardada no es la clave de la bóveda en claro.
    final stored = String.fromCharCodes(keyStore.bytes!);
    expect(stored, isNot(contains('Banco')));

    session.lock();
    await biometric.unlock(session);
    expect(session.status, VaultStatus.unlocked);
    expect(session.entries.single.title, 'Banco');
  });

  test('no se puede activar con la sesión bloqueada', () async {
    session.lock();
    await expectLater(
      biometric.enable(session),
      throwsA(isA<VaultLockedException>()),
    );
    expect(await biometric.isEnabled(), isFalse);
  });

  test('cancelar el diálogo deja la sesión bloqueada', () async {
    await biometric.enable(session);
    session.lock();
    platform.cancelNext = true;
    await expectLater(
      biometric.unlock(session),
      throwsA(isA<BiometricCanceledException>()),
    );
    expect(session.status, VaultStatus.locked);
    expect(await biometric.isEnabled(), isTrue);
  });

  test(
    'si Android invalida la llave, se desactiva y pide la maestra',
    () async {
      await biometric.enable(session);
      session.lock();
      platform.invalidate();
      await expectLater(
        biometric.unlock(session),
        throwsA(isA<BiometricInvalidatedException>()),
      );
      expect(session.status, VaultStatus.locked);
      expect(await biometric.isEnabled(), isFalse);

      // Con la contraseña maestra se entra y se puede reactivar.
      await session.unlock(master);
      await biometric.enable(session);
      session.lock();
      await biometric.unlock(session);
      expect(session.status, VaultStatus.unlocked);
    },
  );

  test('una clave que no corresponde a la bóveda se descarta', () async {
    await biometric.enable(session);
    session.lock();
    // La bóveda se reemplaza por otra (otra contraseña maestra).
    vaultStore.bytes = null;
    final other = VaultSession(
      store: vaultStore,
      cipher: VaultCipher(keyDerivation: ControlledKdf()),
      newKdfParams: fastKdfParams,
    );
    await other.initialize();
    await other.create('otra contraseña maestra');
    other.lock();

    await expectLater(
      biometric.unlock(other),
      throwsA(isA<BiometricInvalidatedException>()),
    );
    expect(other.status, VaultStatus.locked);
    expect(await biometric.isEnabled(), isFalse);
    expect(platform.hasKey, isFalse);
  });

  test(
    'un desbloqueo con huella pendiente no reabre una sesión bloqueada',
    () async {
      await biometric.enable(session);
      session.lock();
      // Bloqueo justo después de iniciar el desbloqueo.
      final pending = biometric.unlock(session);
      session.lock();
      await expectLater(pending, throwsA(isA<VaultLockedException>()));
      expect(session.status, VaultStatus.locked);
      expect(session.entries, isEmpty);
    },
  );

  test('desactivar borra la llave y la clave guardada', () async {
    await biometric.enable(session);
    await biometric.disable();
    expect(await biometric.isEnabled(), isFalse);
    expect(platform.hasKey, isFalse);
  });
}

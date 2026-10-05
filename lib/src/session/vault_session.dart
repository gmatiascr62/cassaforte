import 'dart:async';

import 'package:flutter/foundation.dart';

import '../crypto/kdf.dart';
import '../crypto/vault_cipher.dart';
import '../model/vault_entry.dart';
import '../storage/vault_store.dart';

enum VaultStatus { initializing, needsSetup, locked, unlocked }

/// La bóveda se bloqueó antes de que terminara la operación.
class VaultLockedException implements Exception {
  const VaultLockedException();
  @override
  String toString() => 'VaultLockedException';
}

/// Contraseña incorrecta o contenido cifrado alterado.
class WrongPasswordException implements Exception {
  const WrongPasswordException();
  @override
  String toString() => 'WrongPasswordException';
}

/// El archivo de la bóveda está dañado o no tiene un formato válido.
class VaultCorruptedException implements Exception {
  const VaultCorruptedException();
  @override
  String toString() => 'VaultCorruptedException';
}

/// Ya existe una bóveda y no se va a sobrescribir.
class VaultAlreadyExistsException implements Exception {
  const VaultAlreadyExistsException();
  @override
  String toString() => 'VaultAlreadyExistsException';
}

/// Gestiona el estado de la bóveda: creación, desbloqueo, bloqueo,
/// modificaciones y bloqueo automático por inactividad.
///
/// La clave derivada solo existe en memoria mientras la sesión está
/// desbloqueada. Cada bloqueo incrementa [_epoch]; las operaciones asíncronas
/// capturan el valor al empezar y, si ha cambiado al terminar, descartan su
/// resultado en lugar de reabrir la sesión.
class VaultSession extends ChangeNotifier {
  VaultSession({
    required VaultStore store,
    VaultCipher? cipher,
    KdfParams Function()? newKdfParams,
    this.autoLockAfter = defaultAutoLock,
  }) : _store = store,
       _cipher = cipher ?? VaultCipher(),
       _newKdfParams = newKdfParams ?? KdfParams.generate;

  static const Duration defaultAutoLock = Duration(minutes: 2);

  /// Longitud mínima de la contraseña maestra.
  static const int minMasterPasswordLength = 10;

  final VaultStore _store;
  final VaultCipher _cipher;
  final KdfParams Function() _newKdfParams;
  final Duration autoLockAfter;

  VaultStatus _status = VaultStatus.initializing;
  int _epoch = 0;
  int? _busyEpoch;
  Uint8List? _key;
  KdfParams? _kdf;
  List<VaultEntry> _entries = const [];
  Timer? _idleTimer;
  Future<void> _queue = Future.value();
  bool _disposed = false;

  VaultStatus get status => _status;
  bool get isUnlocked => _status == VaultStatus.unlocked;

  /// Hay una creación o desbloqueo en curso en la sesión actual.
  bool get isBusy => _busyEpoch == _epoch;

  /// Cuentas ordenadas por nombre. Vacío si la sesión está bloqueada.
  List<VaultEntry> get entries => _entries;

  VaultEntry? entryById(String id) {
    for (final e in _entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Comprueba si ya existe una bóveda.
  Future<void> initialize() async {
    final exists = await _store.exists();
    if (_status == VaultStatus.initializing) {
      _status = exists ? VaultStatus.locked : VaultStatus.needsSetup;
      _notify();
    }
  }

  /// Crea una bóveda vacía. Nunca sobrescribe una existente.
  Future<void> create(String masterPassword) async {
    if (_status != VaultStatus.needsSetup || isBusy) {
      throw StateError('No se puede crear la bóveda ahora');
    }
    if (masterPassword.length < minMasterPasswordLength) {
      throw ArgumentError('Contraseña maestra demasiado corta');
    }
    final epoch = _epoch;
    _busyEpoch = epoch;
    _notify();
    Uint8List? key;
    try {
      await _queue;
      if (await _store.exists()) {
        _status = VaultStatus.locked;
        throw const VaultAlreadyExistsException();
      }
      final kdf = _newKdfParams();
      key = await _cipher.deriveKey(masterPassword, kdf);
      final bytes = await _cipher.seal(
        plaintext: Uint8List.fromList(VaultContents.encode(const [])),
        key: key,
        kdf: kdf,
      );
      if (await _store.exists()) {
        _status = VaultStatus.locked;
        throw const VaultAlreadyExistsException();
      }
      await _store.writeAtomic(bytes);
      if (epoch != _epoch) {
        // Se bloqueó durante la creación: la bóveda queda guardada, pero no
        // se abre la sesión.
        _status = VaultStatus.locked;
        throw const VaultLockedException();
      }
      _key = key;
      key = null;
      _kdf = kdf;
      _entries = const [];
      _status = VaultStatus.unlocked;
      _restartIdleTimer();
    } finally {
      _wipe(key);
      if (_busyEpoch == epoch) _busyEpoch = null;
      _notify();
    }
  }

  /// Abre la bóveda. Lanza [WrongPasswordException],
  /// [VaultCorruptedException] o [VaultLockedException].
  Future<void> unlock(String masterPassword) =>
      _unlock((header) => _cipher.deriveKey(masterPassword, header.kdf));

  /// Abre la bóveda con una clave ya derivada (desbloqueo con huella). Una
  /// clave incorrecta se rechaza igual que una contraseña incorrecta.
  ///
  /// [startedAt] es el valor de [lockGeneration] cuando empezó la operación
  /// (antes del diálogo de huella): si la sesión se bloqueó desde entonces,
  /// no se abre.
  Future<void> unlockWithKey(Uint8List key, {int? startedAt}) {
    if (startedAt != null && startedAt != _epoch) {
      return Future.error(const VaultLockedException());
    }
    return _unlock((_) async => Uint8List.fromList(key));
  }

  /// Cambia cada vez que se bloquea la sesión.
  int get lockGeneration => _epoch;

  Future<void> _unlock(
    Future<Uint8List> Function(VaultHeader header) obtainKey,
  ) async {
    if (_status != VaultStatus.locked || isBusy) {
      throw StateError('No se puede desbloquear ahora');
    }
    final epoch = _epoch;
    _busyEpoch = epoch;
    _notify();
    Uint8List? key;
    try {
      // Espera a que termine cualquier guardado pendiente antes de leer.
      await _queue;
      final bytes = await _store.read();
      final header = _readHeader(bytes);
      if (epoch != _epoch) throw const VaultLockedException();
      key = await obtainKey(header);
      if (epoch != _epoch) throw const VaultLockedException();
      final entries = await _decryptEntries(bytes, key);
      if (epoch != _epoch || _status != VaultStatus.locked) {
        throw const VaultLockedException();
      }
      _key = key;
      key = null;
      _kdf = header.kdf;
      _entries = _sorted(entries);
      _status = VaultStatus.unlocked;
      _restartIdleTimer();
    } finally {
      _wipe(key);
      if (_busyEpoch == epoch) _busyEpoch = null;
      _notify();
    }
  }

  /// Descifra un archivo de copia de seguridad (mismo formato que la
  /// bóveda) con su contraseña. No modifica nada.
  Future<List<VaultEntry>> openBackup(Uint8List bytes, String password) async {
    final header = _readHeader(bytes);
    final key = await _cipher.deriveKey(password, header.kdf);
    try {
      return await _decryptEntries(bytes, key);
    } finally {
      _wipe(key);
    }
  }

  /// Primera ejecución: restaura una copia de seguridad como bóveda nueva.
  /// La contraseña maestra pasa a ser la de la copia. Nunca sobrescribe una
  /// bóveda existente.
  Future<void> restoreBackup(Uint8List bytes, String password) async {
    if (_status != VaultStatus.needsSetup || isBusy) {
      throw StateError('No se puede restaurar ahora');
    }
    final epoch = _epoch;
    _busyEpoch = epoch;
    _notify();
    Uint8List? key;
    try {
      await _queue;
      if (await _store.exists()) {
        _status = VaultStatus.locked;
        throw const VaultAlreadyExistsException();
      }
      final header = _readHeader(bytes);
      key = await _cipher.deriveKey(password, header.kdf);
      final entries = await _decryptEntries(bytes, key);
      if (await _store.exists()) {
        _status = VaultStatus.locked;
        throw const VaultAlreadyExistsException();
      }
      // El archivo ya está cifrado y autenticado: se guarda tal cual.
      await _store.writeAtomic(Uint8List.fromList(bytes));
      if (epoch != _epoch) {
        _status = VaultStatus.locked;
        throw const VaultLockedException();
      }
      _key = key;
      key = null;
      _kdf = header.kdf;
      _entries = _sorted(entries);
      _status = VaultStatus.unlocked;
      _restartIdleTimer();
    } finally {
      _wipe(key);
      if (_busyEpoch == epoch) _busyEpoch = null;
      _notify();
    }
  }

  /// Devuelve el archivo cifrado de la bóveda para guardarlo como copia de
  /// seguridad. Exige la contraseña maestra para asegurarse de que el
  /// usuario la recuerda: sin ella la copia no sirve.
  Future<Uint8List> exportBackup(String masterPassword) async {
    final key = _key;
    if (_status != VaultStatus.unlocked || key == null) {
      throw const VaultLockedException();
    }
    final epoch = _epoch;
    final keyCopy = Uint8List.fromList(key);
    Uint8List? derived;
    try {
      await _queue;
      final bytes = await _store.read();
      final header = _readHeader(bytes);
      derived = await _cipher.deriveKey(masterPassword, header.kdf);
      if (!_constantTimeEquals(derived, keyCopy)) {
        throw const WrongPasswordException();
      }
      if (epoch != _epoch) throw const VaultLockedException();
      return bytes;
    } finally {
      _wipe(keyCopy);
      _wipe(derived);
    }
  }

  /// Añade cuentas de una copia. Con [replace], sustituye todas las cuentas
  /// actuales; si no, las fusiona (ver [mergeEntries]). La contraseña
  /// maestra actual no cambia.
  Future<MergeResult> importEntries(
    List<VaultEntry> incoming, {
    required bool replace,
  }) async {
    late MergeResult result;
    await _mutate((current) {
      result = replace
          ? MergeResult(List.of(incoming), added: incoming.length, updated: 0)
          : mergeEntries(current, incoming);
      return result.entries;
    });
    return result;
  }

  /// Ejecuta [action] con una copia de la clave (para protegerla con la
  /// huella). La copia se borra al terminar.
  Future<T> withKey<T>(Future<T> Function(Uint8List key) action) async {
    final key = _key;
    if (_status != VaultStatus.unlocked || key == null) {
      throw const VaultLockedException();
    }
    final copy = Uint8List.fromList(key);
    try {
      return await action(copy);
    } finally {
      _wipe(copy);
    }
  }

  VaultHeader _readHeader(Uint8List bytes) {
    try {
      return _cipher.readHeader(bytes);
    } on VaultFormatException {
      throw const VaultCorruptedException();
    }
  }

  Future<List<VaultEntry>> _decryptEntries(
    Uint8List bytes,
    Uint8List key,
  ) async {
    final Uint8List clear;
    try {
      clear = await _cipher.open(fileBytes: bytes, key: key);
    } on VaultAuthenticationException {
      throw const WrongPasswordException();
    } on VaultFormatException {
      throw const VaultCorruptedException();
    }
    try {
      return VaultContents.decode(clear);
    } on FormatException {
      throw const VaultCorruptedException();
    } finally {
      clear.fillRange(0, clear.length, 0);
    }
  }

  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// Bloquea la sesión inmediatamente y borra la clave de la memoria.
  void lock() {
    _epoch++;
    _idleTimer?.cancel();
    _idleTimer = null;
    _wipe(_key);
    _key = null;
    _kdf = null;
    _entries = const [];
    if (_status == VaultStatus.unlocked) {
      _status = VaultStatus.locked;
    }
    _notify();
  }

  /// Reinicia el temporizador de inactividad.
  void registerActivity() {
    if (_status == VaultStatus.unlocked) _restartIdleTimer();
  }

  /// Añade una cuenta o sustituye la que tenga el mismo id.
  Future<void> saveEntry(VaultEntry entry) => _mutate((list) {
    final index = list.indexWhere((e) => e.id == entry.id);
    if (index >= 0) {
      list[index] = entry;
    } else {
      list.add(entry);
    }
    return list;
  });

  Future<void> deleteEntry(String id) =>
      _mutate((list) => list..removeWhere((e) => e.id == id));

  /// Las modificaciones se encadenan para que dos guardados no se pisen.
  Future<void> _mutate(List<VaultEntry> Function(List<VaultEntry>) change) {
    final run = _queue.then((_) => _applyMutation(change));
    _queue = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<void> _applyMutation(
    List<VaultEntry> Function(List<VaultEntry>) change,
  ) async {
    final epoch = _epoch;
    final key = _key;
    final kdf = _kdf;
    if (_status != VaultStatus.unlocked || key == null || kdf == null) {
      throw const VaultLockedException();
    }
    final next = _sorted(change(List.of(_entries)));
    // Copia de la clave para que un bloqueo concurrente pueda borrar la
    // original sin corromper el cifrado en curso.
    final keyCopy = Uint8List.fromList(key);
    try {
      final bytes = await _cipher.seal(
        plaintext: Uint8List.fromList(VaultContents.encode(next)),
        key: keyCopy,
        kdf: kdf,
      );
      // Si la sesión se bloqueó mientras tanto, el cambio se guarda igualmente
      // (el archivo queda completo y cifrado) pero la sesión no se reabre.
      await _store.writeAtomic(bytes);
      if (epoch != _epoch) throw const VaultLockedException();
      _entries = next;
      _restartIdleTimer();
      _notify();
    } finally {
      _wipe(keyCopy);
    }
  }

  void _restartIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(autoLockAfter, lock);
  }

  static List<VaultEntry> _sorted(List<VaultEntry> list) {
    final copy = List.of(list)
      ..sort((a, b) {
        final c = a.title.toLowerCase().compareTo(b.title.toLowerCase());
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    return List.unmodifiable(copy);
  }

  static void _wipe(Uint8List? bytes) {
    bytes?.fillRange(0, bytes.length, 0);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    lock();
    _disposed = true;
    super.dispose();
  }
}

import 'dart:io';
import 'dart:typed_data';

import 'package:cassaforte/src/storage/vault_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late String path;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cassaforte_store_');
    path = '${dir.path}/${FileVaultStore.fileName}';
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('escribe, lee y sustituye el contenido', () async {
    final store = FileVaultStore(path);
    expect(await store.exists(), isFalse);
    await store.writeAtomic(Uint8List.fromList([1, 2, 3]));
    expect(await store.exists(), isTrue);
    expect(await store.read(), [1, 2, 3]);
    await store.writeAtomic(Uint8List.fromList([4, 5]));
    expect(await store.read(), [4, 5]);
    expect(await File('$path.tmp').exists(), isFalse);
  });

  test('si la escritura falla, el archivo anterior queda intacto', () async {
    final store = FileVaultStore(path);
    await store.writeAtomic(Uint8List.fromList([9, 9, 9]));
    // Un directorio en la ruta temporal hace fallar la escritura.
    await Directory('$path.tmp').create();
    await expectLater(
      store.writeAtomic(Uint8List.fromList([1, 1, 1, 1])),
      throwsA(isA<FileSystemException>()),
    );
    expect(await store.read(), [9, 9, 9]);
  });

  test(
    'ignora y reemplaza un temporal incompleto de un fallo anterior',
    () async {
      final store = FileVaultStore(path);
      await store.writeAtomic(Uint8List.fromList([7, 7]));
      await File('$path.tmp').writeAsBytes([0, 0, 0, 0, 0, 0]);
      expect(await store.read(), [7, 7]);
      await store.writeAtomic(Uint8List.fromList([8]));
      expect(await store.read(), [8]);
      expect(await File('$path.tmp').exists(), isFalse);
    },
  );
}

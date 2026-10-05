import 'dart:convert';
import 'dart:typed_data';

import 'package:cassaforte/src/crypto/kdf.dart';
import 'package:cassaforte/src/crypto/vault_cipher.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List mutateJson(
  Uint8List file,
  void Function(Map<String, dynamic> doc) change,
) {
  final doc = jsonDecode(utf8.decode(file)) as Map<String, dynamic>;
  change(doc);
  return Uint8List.fromList(utf8.encode(jsonEncode(doc)));
}

void main() {
  group('Primitivas', () {
    test(
      'Argon2id coincide con el vector de prueba de RFC 9106 (5.3)',
      () async {
        const algorithm = DartArgon2id(
          memory: 32,
          iterations: 3,
          parallelism: 4,
          hashLength: 32,
        );
        final key = await algorithm.deriveKey(
          secretKey: SecretKey(List.filled(32, 0x01)),
          nonce: List.filled(16, 0x02),
          optionalSecret: List.filled(8, 0x03),
          associatedData: List.filled(12, 0x04),
        );
        expect(
          hex(await key.extractBytes()),
          '0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659',
        );
      },
    );

    test('AES-256-GCM coincide con el vector de prueba 14 de GCM', () async {
      final aes = AesGcm.with256bits();
      final box = await aes.encrypt(
        List.filled(16, 0),
        secretKey: SecretKey(List.filled(32, 0)),
        nonce: List.filled(12, 0),
      );
      expect(hex(box.cipherText), 'cea7403d4d606b6e074ec5d3baf39d18');
      expect(hex(box.mac.bytes), 'd0d1c8a799996bf0265b98b5d48ab919');
    });
  });

  group('Derivación de clave', () {
    const kdf = Argon2idKeyDerivation();

    test('es determinista y depende de contraseña y sal', () async {
      final params = fastKdfParams();
      final a = await kdf.deriveKey('contraseña larga', params);
      final b = await kdf.deriveKey('contraseña larga', params);
      final c = await kdf.deriveKey('contraseña Larga', params);
      final d = await kdf.deriveKey('contraseña larga', fastKdfParams());
      expect(a, hasLength(32));
      expect(a, b);
      expect(a, isNot(c));
      expect(a, isNot(d));
    });

    test('los parámetros por defecto son los documentados', () {
      final params = KdfParams.generate();
      expect(params.memoryKiB, 65536);
      expect(params.iterations, 3);
      expect(params.parallelism, 4);
      expect(params.salt, hasLength(16));
      expect(params.isValid, isTrue);
      expect(KdfParams.generate().salt, isNot(params.salt));
    });
  });

  group('VaultCipher', () {
    late VaultCipher cipher;
    late KdfParams params;
    late Uint8List key;
    final plaintext = Uint8List.fromList(utf8.encode('{"secreto":"hola"}'));

    setUp(() async {
      cipher = VaultCipher();
      params = fastKdfParams();
      key = await cipher.deriveKey('maestra-de-prueba', params);
    });

    test('cifra y descifra', () async {
      final file = await cipher.seal(
        plaintext: plaintext,
        key: key,
        kdf: params,
      );
      final clear = await cipher.open(fileBytes: file, key: key);
      expect(clear, plaintext);
    });

    test('no deja el contenido en claro en el archivo', () async {
      final file = await cipher.seal(
        plaintext: plaintext,
        key: key,
        kdf: params,
      );
      expect(utf8.decode(file), isNot(contains('secreto')));
      expect(utf8.decode(file), isNot(contains('hola')));
    });

    test('usa un nonce distinto en cada cifrado', () async {
      final nonces = <String>{};
      for (var i = 0; i < 50; i++) {
        final file = await cipher.seal(
          plaintext: plaintext,
          key: key,
          kdf: params,
        );
        nonces.add(base64.encode(cipher.readHeader(file).nonce));
      }
      expect(nonces, hasLength(50));
    });

    test('rechaza una clave incorrecta', () async {
      final file = await cipher.seal(
        plaintext: plaintext,
        key: key,
        kdf: params,
      );
      final wrong = await cipher.deriveKey('otra-contraseña', params);
      expect(
        () => cipher.open(fileBytes: file, key: wrong),
        throwsA(isA<VaultAuthenticationException>()),
      );
    });

    test('detecta la alteración de cualquier byte del texto cifrado', () async {
      final file = await cipher.seal(
        plaintext: plaintext,
        key: key,
        kdf: params,
      );
      final doc = jsonDecode(utf8.decode(file)) as Map<String, dynamic>;
      final data = base64.decode(doc['ciphertext'] as String);
      for (var i = 0; i < data.length; i++) {
        final altered = Uint8List.fromList(data)..[i] ^= 0x01;
        final tampered = mutateJson(
          file,
          (d) => d['ciphertext'] = base64.encode(altered),
        );
        await expectLater(
          cipher.open(fileBytes: tampered, key: key),
          throwsA(isA<VaultAuthenticationException>()),
          reason: 'byte $i',
        );
      }
    });

    test('detecta la alteración del nonce', () async {
      final file = await cipher.seal(
        plaintext: plaintext,
        key: key,
        kdf: params,
      );
      final tampered = mutateJson(file, (d) {
        final nonce = base64.decode(d['cipher']['nonce'] as String);
        nonce[0] ^= 0xff;
        d['cipher']['nonce'] = base64.encode(nonce);
      });
      expect(
        () => cipher.open(fileBytes: tampered, key: key),
        throwsA(isA<VaultAuthenticationException>()),
      );
    });

    test('autentica los parámetros de la cabecera', () async {
      final file = await cipher.seal(
        plaintext: plaintext,
        key: key,
        kdf: params,
      );
      final changes = <void Function(Map<String, dynamic>)>[
        (d) => d['kdf']['iterations'] = 2,
        (d) => d['kdf']['memoryKiB'] = 128,
        (d) {
          final salt = base64.decode(d['kdf']['salt'] as String);
          salt[3] ^= 0x10;
          d['kdf']['salt'] = base64.encode(salt);
        },
      ];
      for (final change in changes) {
        // Se usa la clave correcta: aun así debe fallar por la AAD.
        await expectLater(
          cipher.open(fileBytes: mutateJson(file, change), key: key),
          throwsA(isA<VaultAuthenticationException>()),
        );
      }
    });

    test('rechaza archivos con formato no válido', () async {
      final file = await cipher.seal(
        plaintext: plaintext,
        key: key,
        kdf: params,
      );
      final invalid = <Uint8List>[
        Uint8List(0),
        Uint8List.fromList(utf8.encode('no es json')),
        Uint8List.fromList([0xff, 0xfe, 0x00]),
        mutateJson(file, (d) => d['format'] = 'otro'),
        mutateJson(file, (d) => d['version'] = 2),
        mutateJson(file, (d) => d['cipher']['algorithm'] = 'aes-128-cbc'),
        mutateJson(file, (d) => d['kdf']['algorithm'] = 'pbkdf2'),
        mutateJson(file, (d) => d['kdf']['memoryKiB'] = 1 << 30),
        mutateJson(file, (d) => d['kdf']['iterations'] = 0),
        mutateJson(file, (d) => d['kdf']['salt'] = 'AAAA'),
        mutateJson(file, (d) => d['cipher']['nonce'] = 'AAAA'),
        mutateJson(file, (d) => d['ciphertext'] = 'AAAA'),
        mutateJson(file, (d) => d['ciphertext'] = '%%%'),
        mutateJson(file, (d) => d.remove('kdf')),
      ];
      for (final bytes in invalid) {
        await expectLater(
          cipher.open(fileBytes: bytes, key: key),
          throwsA(isA<VaultFormatException>()),
        );
      }
    });
  });
}

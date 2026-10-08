import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cassaforte/src/backup/base45.dart';
import 'package:cassaforte/src/backup/qr_backup_cipher.dart';
import 'package:cassaforte/src/backup/qr_chunks.dart';
import 'package:cassaforte/src/backup/qr_codes.dart';
import 'package:cassaforte/src/backup/qr_image_reader.dart';
import 'package:cassaforte/src/model/vault_entry.dart';
import 'package:flutter_test/flutter_test.dart';

import 'backup_page_renderer.dart';
import 'helpers.dart';

const master = 'mi contraseña maestra';

QrBackupCipher fastCipher() => QrBackupCipher(newKdfParams: fastKdfParams);

/// Cuentas realistas: contraseñas aleatorias, campos extra y notas.
List<VaultEntry> sampleAccounts(int n, {int seed = 7}) {
  final r = Random(seed);
  String rnd(
    int len, [
    String chars =
        'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!#%&*+-=?@',
  ]) => String.fromCharCodes(
    List.generate(len, (_) => chars.codeUnitAt(r.nextInt(chars.length))),
  );
  const sites = [
    'Banco Nación',
    'Gmail',
    'Netflix',
    'Mercado Libre',
    'AFIP',
    'Spotify',
    'Steam',
    'Correo del trabajo',
  ];
  return [
    for (var i = 0; i < n; i++)
      VaultEntry.create(
        title: '${sites[i % sites.length]} $i',
        url: i.isEven
            ? 'https://www.${rnd(8, 'abcdefghijklmnopqrstuvwxyz')}.com/login'
            : '',
        username: 'usuario.$i@ejemplo.com',
        password: rnd(20),
        notes: i % 5 == 0
            ? 'Preguntas de seguridad: ${rnd(12)} ñandú «$i»'
            : '',
        fields: i % 3 == 0
            ? [
                CustomField(
                  label: 'PIN',
                  value: rnd(4, '0123456789'),
                  hidden: true,
                ),
              ]
            : const [],
        now: DateTime.utc(2025, 1, 1).add(Duration(minutes: i)),
      ),
  ];
}

void expectSameEntries(List<VaultEntry> actual, List<VaultEntry> expected) {
  expect(actual.length, expected.length);
  final byId = {for (final e in actual) e.id: e};
  for (final e in expected) {
    final a = byId[e.id]!;
    expect(a.title, e.title);
    expect(a.url, e.url);
    expect(a.username, e.username);
    expect(a.password, e.password);
    expect(a.notes, e.notes);
    expect(a.fields, e.fields);
    expect(a.createdAt, e.createdAt);
    expect(a.updatedAt, e.updatedAt);
  }
}

Future<List<String>> exportCodes(
  List<VaultEntry> entries, {
  String pw = master,
}) async {
  final payload = await fastCipher().seal(entries, pw);
  return QrChunk.split(payload, isReadable: isQrReadable);
}

void main() {
  group('Base45', () {
    test('ida y vuelta con datos binarios de cualquier longitud', () {
      final r = Random(3);
      for (var len = 0; len < 300; len++) {
        final data = Uint8List.fromList(
          List.generate(len, (_) => r.nextInt(256)),
        );
        expect(Base45.decode(Base45.encode(data)), data);
      }
    });

    test('vector del RFC 9285', () {
      expect(
        Base45.encode(Uint8List.fromList(utf8.encode('Hello!!'))),
        '%69 VD92EX0',
      );
      expect(utf8.decode(Base45.decode('QED8WEX0')), 'ietf!');
    });

    test('rechaza texto no válido', () {
      for (final bad in ['A', 'abc', 'GGW', 'ZZZ', 'A#B']) {
        expect(() => Base45.decode(bad), throwsFormatException);
      }
    });
  });

  group('Exportar y restaurar', () {
    for (final n in [1, 20, 50, 100]) {
      test('$n cuentas: PDF → lectura de QR → restauración exacta', () async {
        final entries = sampleAccounts(n);
        final raster = FakeRasterizer();
        final service = TestQrBackupService(kdf: FakeKdf(), raster: raster);
        final backup = await service.createPdf(entries, master);
        raster.codes = backup.codeTexts;
        // ignore: avoid_print
        print('$n cuentas → ${backup.codes} QR en ${backup.pages} hoja(s)');

        final assembler = BackupAssembler();
        await service.readPdf(backup.pdf, assembler);
        expect(assembler.isComplete, isTrue);
        final restored = await service.open(assembler.assemble(), master);
        expectSameEntries(restored, entries);
      });
    }

    test('10 copias de 100 cuentas se leen completas desde el PDF', () async {
      for (var round = 0; round < 10; round++) {
        final raster = FakeRasterizer();
        final service = TestQrBackupService(kdf: FakeKdf(), raster: raster);
        final backup = await service.createPdf(
          sampleAccounts(100, seed: round),
          master,
        );
        raster.codes = backup.codeTexts;
        final assembler = BackupAssembler();
        await service.readPdf(backup.pdf, assembler);
        expect(assembler.isComplete, isTrue, reason: 'copia $round');
      }
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('lee hojas desplazadas (como un PDF escaneado de papel)', () async {
      final codes = await exportCodes(sampleAccounts(50));
      // Como readPdf: si a una resolución falta algún código (al detector
      // de ZXing le cuesta algún QR con un tamaño de módulo concreto), se
      // relee a otra.
      final found = <String>{};
      for (final dpi in const [150.0, 300.0]) {
        final page = renderPages(codes, dpi: dpi).first;
        final w = page.width, h = page.height;
        final dx = (37 * dpi / 150).round(), dy = (53 * dpi / 150).round();
        final shifted = Uint8List(w * h)..fillRange(0, w * h, 255);
        for (var y = 0; y < h - dy; y++) {
          shifted.setRange(
            (y + dy) * w + dx,
            (y + dy + 1) * w,
            page.pixels,
            y * w,
          );
        }
        found.addAll(QrImageReader.readAll(GrayImage(w, h, shifted)));
        if (found.length == 6) break;
      }
      expect(found, codes.take(6).toSet());
    });

    test('100 cuentas típicas caben en pocas hojas', () async {
      final codes = await exportCodes(sampleAccounts(100));
      expect(codes.length, lessThanOrEqualTo(30));
      for (final c in codes) {
        expect(c.length, lessThanOrEqualTo(970)); // QR versión ≤ 20 (M)
      }
    });

    test('los códigos desordenados y repetidos se reconstruyen', () async {
      final entries = sampleAccounts(30);
      final codes = await exportCodes(entries);
      final shuffled = [...codes, ...codes.take(3)]..shuffle(Random(1));
      final assembler = BackupAssembler();
      var duplicates = 0;
      for (final c in shuffled) {
        final status = assembler.add(c);
        if (status == ChunkStatus.duplicate) duplicates++;
        expect(status, anyOf(ChunkStatus.added, ChunkStatus.duplicate));
      }
      expect(duplicates, 3);
      expectSameEntries(
        await fastCipher().open(assembler.assemble(), master),
        entries,
      );
    });

    test('detecta códigos faltantes', () async {
      final codes = await exportCodes(sampleAccounts(30));
      final assembler = BackupAssembler();
      for (var i = 0; i < codes.length; i++) {
        if (i != 1 && i != 3) assembler.add(codes[i]);
      }
      expect(assembler.isComplete, isFalse);
      expect(assembler.missing, [2, 4]);
      expect(assembler.assemble, throwsA(isA<BackupFormatException>()));
    });

    test('rechaza códigos de otra copia', () async {
      final a = await exportCodes(sampleAccounts(10));
      final b = await exportCodes(sampleAccounts(10));
      final assembler = BackupAssembler();
      expect(assembler.add(a.first), ChunkStatus.added);
      expect(assembler.add(b.first), ChunkStatus.otherCopy);
      expect(assembler.add(b.last), ChunkStatus.otherCopy);
      expect(assembler.received, 1);
    });

    test('rechaza códigos ajenos o dañados', () async {
      final codes = await exportCodes(sampleAccounts(5));
      final assembler = BackupAssembler();
      expect(assembler.add('https://ejemplo.com'), ChunkStatus.invalid);
      expect(assembler.add('HOLA MUNDO'), ChunkStatus.invalid);
      // Un carácter cambiado: falla la suma de control del fragmento.
      final c = codes.first;
      final damaged =
          '${c.substring(0, 40)}${c[40] == 'A' ? 'B' : 'A'}${c.substring(41)}';
      expect(assembler.add(damaged), ChunkStatus.invalid);
      expect(assembler.received, 0);
    });

    test(
      'detecta un fragmento falsificado aunque tenga suma de control válida',
      () async {
        final entries = sampleAccounts(10);
        final payload = await fastCipher().seal(entries, master);
        final codes = QrChunk.split(payload);
        // Se rehace el primer fragmento con datos alterados pero coherente.
        final first = QrChunk.parse(codes.first);
        final altered = Uint8List.fromList(first.data)..[5] ^= 0xFF;
        final forged = _forge(first, altered);
        final assembler = BackupAssembler()..add(forged);
        for (final c in codes.skip(1)) {
          assembler.add(c);
        }
        expect(assembler.isComplete, isTrue);
        expect(assembler.assemble, throwsA(isA<BackupFormatException>()));
        // Y si llega el auténtico después, se marca como conflicto.
        expect(assembler.add(codes.first), ChunkStatus.conflict);
      },
    );

    test('contraseña maestra incorrecta', () async {
      final payload = await fastCipher().seal(sampleAccounts(5), master);
      await expectLater(
        fastCipher().open(payload, 'otra contraseña'),
        throwsA(isA<BackupWrongPasswordException>()),
      );
    });

    test('datos cifrados alterados', () async {
      final payload = await fastCipher().seal(sampleAccounts(5), master);
      for (final i in [5, 12, 30, 45, payload.length - 1]) {
        final altered = Uint8List.fromList(payload)..[i] ^= 0x01;
        await expectLater(
          fastCipher().open(altered, master),
          throwsA(
            anyOf(
              isA<BackupWrongPasswordException>(),
              isA<BackupFormatException>(),
            ),
          ),
          reason: 'byte $i',
        );
      }
    });

    test('rechaza formatos y parámetros no válidos', () async {
      final payload = await fastCipher().seal(sampleAccounts(2), master);
      Uint8List edit(void Function(Uint8List b) f) =>
          Uint8List.fromList(payload)..apply(f);
      final invalid = [
        Uint8List(0),
        Uint8List(30),
        edit((b) => b[0] = 0x00), // identificador
        edit((b) => b[4] = 9), // versión
        edit(
          (b) => ByteData.sublistView(b).setUint32(5, 0xFFFFFFFF),
        ), // memoria
        edit((b) => b[9] = 0), // pasadas
        edit((b) => b[10] = 200), // carriles
      ];
      for (final bytes in invalid) {
        await expectLater(
          fastCipher().open(bytes, master),
          throwsA(isA<BackupFormatException>()),
        );
      }
    });

    test('limita la descompresión (bomba de compresión)', () {
      final bomb = Uint8List.fromList(
        gzip.encode(Uint8List(QrBackupCipher.maxDecompressedBytes + 1)),
      );
      expect(
        () => gunzipLimited(bomb, QrBackupCipher.maxDecompressedBytes),
        throwsA(isA<BackupFormatException>()),
      );
      expect(
        () => gunzipLimited(Uint8List.fromList([1, 2, 3]), 100),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('los QR no contienen datos en claro', () async {
      final entries = sampleAccounts(20);
      final codes = await exportCodes(entries);
      final all = codes.join();
      final decoded = codes
          .map((c) => latin1.decode(Base45.decode(c), allowInvalid: true))
          .join();
      for (final e in entries) {
        for (final secret in [e.title, e.username, e.password]) {
          expect(all.contains(secret.toUpperCase()), isFalse);
          expect(decoded.contains(secret), isFalse);
        }
      }
    });

    test('funciona sin conexión: no se usa ninguna conexión de red', () async {
      await HttpOverrides.runZoned(() async {
        final entries = sampleAccounts(20);
        final codes = await exportCodes(entries);
        final assembler = BackupAssembler();
        for (final page in renderPages(codes)) {
          QrImageReader.readAll(page).forEach(assembler.add);
        }
        expectSameEntries(
          await fastCipher().open(assembler.assemble(), master),
          entries,
        );
      }, createHttpClient: (_) => throw StateError('Sin red'));
    });
  });
}

String _forge(QrChunk c, Uint8List data) => QrChunk.encodeForTest(
  QrChunk(copyId: c.copyId, index: c.index, total: c.total, data: data),
);

extension on Uint8List {
  void apply(void Function(Uint8List b) f) => f(this);
}

import 'dart:isolate';
import 'dart:typed_data';

import 'package:printing/printing.dart';

import '../model/vault_entry.dart';
import 'backup_pdf.dart';
import 'qr_backup_cipher.dart';
import 'qr_chunks.dart';
import 'qr_codes.dart';
import 'qr_image_reader.dart';
import 'qr_page_layout.dart';

/// Copia lista para guardar, imprimir o compartir.
class PdfBackup {
  const PdfBackup({
    required this.pdf,
    required this.copyId,
    required this.codes,
    required this.pages,
    required this.codeTexts,
  });

  /// El PDF (contiene solo datos cifrados).
  final Uint8List pdf;

  /// Identificador corto de la copia (8 caracteres hexadecimales).
  final String copyId;
  final int codes;
  final int pages;

  /// Texto de cada QR, en orden (datos cifrados en Base45).
  final List<String> codeTexts;

  String get shortId => '${copyId.substring(0, 4)}-${copyId.substring(4, 8)}';

  String get fileName => 'cassaforte-copia-$shortId.pdf';
}

/// Convierte cada hoja de un PDF en una imagen en escala de grises.
abstract interface class PdfRasterizer {
  Stream<GrayImage> rasterize(Uint8List pdf, {required double dpi});
}

/// Usa el renderizador de PDF de Android (PdfRenderer) a través del paquete
/// `printing`. Todo ocurre en el teléfono, sin conexión.
class PrintingPdfRasterizer implements PdfRasterizer {
  const PrintingPdfRasterizer();

  @override
  Stream<GrayImage> rasterize(Uint8List pdf, {required double dpi}) async* {
    await for (final page in Printing.raster(pdf, dpi: dpi)) {
      final w = page.width, h = page.height;
      final rgba = page.pixels;
      yield await Isolate.run(() => GrayImage.fromRgba(w, h, rgba));
    }
  }
}

/// Exportación y lectura de copias de seguridad en PDF con códigos QR.
class QrBackupService {
  QrBackupService({
    QrBackupCipher? cipher,
    PdfRasterizer? rasterizer,
    Future<List<String>> Function(GrayImage page)? pageDecoder,
    Future<List<String>> Function(Uint8List payload)? codeEncoder,
  }) : cipher = cipher ?? QrBackupCipher(),
       _rasterizer = rasterizer ?? const PrintingPdfRasterizer(),
       _decodePage = pageDecoder ?? _decodeInIsolate,
       _encodeCodes = codeEncoder ?? _encodeInIsolate;

  /// Cada QR se comprueba antes de ponerlo en el PDF (en otro isolate).
  static Future<List<String>> _encodeInIsolate(Uint8List payload) =>
      Isolate.run(() => QrChunk.split(payload, isReadable: isQrReadable));

  static Future<List<String>> _decodeInIsolate(GrayImage page) =>
      Isolate.run(() => QrImageReader.readAll(page));

  /// Límites para no procesar archivos maliciosos o absurdos.
  static const int maxPdfBytes = 30 * 1024 * 1024;
  static const int maxPdfPages = 100;

  /// Resoluciones a las que se lee el PDF: si faltan códigos tras la
  /// primera lectura, se vuelve a intentar a otra resolución (el detector
  /// de QR puede fallar con un tamaño de módulo concreto).
  static const List<double> readDpis = [200, 300, 150];

  final QrBackupCipher cipher;
  final PdfRasterizer _rasterizer;
  final Future<List<String>> Function(GrayImage page) _decodePage;
  final Future<List<String>> Function(Uint8List payload) _encodeCodes;

  /// Cifra las cuentas con la contraseña maestra y genera el PDF.
  Future<PdfBackup> createPdf(
    List<VaultEntry> entries,
    String masterPassword,
  ) async {
    final payload = await cipher.seal(entries, masterPassword);
    final codes = await _encodeCodes(payload);
    final copyId = QrChunk.hexId(QrChunk.copyIdOf(payload));
    final pdf = await buildBackupPdf(codes: codes, copyId: copyId);
    return PdfBackup(
      pdf: pdf,
      copyId: copyId,
      codes: codes.length,
      pages: QrPageLayout.pageCount(codes.length),
      codeTexts: codes,
    );
  }

  /// ¿Parece un PDF? (cabecera `%PDF-`).
  static bool looksLikePdf(Uint8List bytes) =>
      bytes.length > 5 &&
      bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46 &&
      bytes[4] == 0x2D;

  /// Lee los QR de todas las hojas del PDF y los añade a [assembler].
  /// Lanza [BackupFormatException] si el archivo no es un PDF válido o no
  /// contiene códigos de Cassaforte.
  Future<void> readPdf(
    Uint8List pdf,
    BackupAssembler assembler, {
    void Function(int page, int codesFound)? onProgress,
  }) async {
    if (!looksLikePdf(pdf) || pdf.length > maxPdfBytes) {
      throw const BackupFormatException('El archivo no es un PDF válido');
    }
    var pages = 0;
    var found = 0;
    var foreign = 0;
    try {
      for (final dpi in readDpis) {
        var page = 0;
        await for (final image in _rasterizer.rasterize(pdf, dpi: dpi)) {
          page++;
          if (page > maxPdfPages) break;
          final texts = await _decodePage(image);
          for (final t in texts) {
            switch (assembler.add(t)) {
              case ChunkStatus.added:
              case ChunkStatus.duplicate:
                found++;
              case ChunkStatus.otherCopy:
              case ChunkStatus.conflict:
              case ChunkStatus.invalid:
                foreign++;
            }
          }
          onProgress?.call(page, found);
        }
        pages = page;
        // Completo, sin páginas o sin ningún código: no vale la pena seguir.
        if (assembler.isComplete || page == 0 || found == 0) break;
      }
    } on BackupFormatException {
      rethrow;
    } catch (_) {
      throw const BackupFormatException('No se pudo leer el PDF');
    }
    if (pages == 0) {
      throw const BackupFormatException('El PDF no tiene páginas');
    }
    if (found == 0) {
      throw BackupFormatException(
        foreign > 0
            ? 'Los códigos del PDF no son de esta copia o están dañados'
            : 'El PDF no contiene códigos de una copia de Cassaforte',
      );
    }
  }

  Future<List<VaultEntry>> open(Uint8List payload, String masterPassword) =>
      cipher.open(payload, masterPassword);
}

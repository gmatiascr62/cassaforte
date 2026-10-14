import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr/qr.dart';

import 'qr_codes.dart';
import 'qr_page_layout.dart';

/// Crea el PDF de la copia: solo códigos QR, la numeración técnica y el
/// identificador de la copia. No incluye ningún dato de las cuentas en
/// texto legible.
Future<Uint8List> buildBackupPdf({
  required List<String> codes,
  required String copyId,
  bool compress = true,
}) {
  final doc = pw.Document(
    compress: compress,
    title: 'Cassaforte',
    creator: 'Cassaforte',
    producer: 'Cassaforte',
  );
  final pages = QrPageLayout.pageCount(codes.length);
  final shortId = '${copyId.substring(0, 4)}-${copyId.substring(4, 8)}';
  const textStyle = pw.TextStyle(fontSize: 9, color: PdfColors.grey800);

  for (var page = 0; page < pages; page++) {
    final slots = [
      for (var slot = 0; slot < QrPageLayout.perPage; slot++)
        if (page * QrPageLayout.perPage + slot < codes.length) slot,
    ];
    doc.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(
          QrPageLayout.pageWidth,
          QrPageLayout.pageHeight,
        ),
        margin: pw.EdgeInsets.zero,
        build: (context) => pw.Stack(
          children: [
            pw.Positioned(
              left: QrPageLayout.margin,
              top: QrPageLayout.margin,
              child: pw.Text(
                'Cassaforte - Copia $shortId - Hoja ${page + 1} de $pages',
                style: textStyle,
              ),
            ),
            for (final slot in slots)
              ..._qrWithLabel(
                codes,
                page * QrPageLayout.perPage + slot,
                slot,
                textStyle,
              ),
          ],
        ),
      ),
    );
  }
  return doc.save();
}

List<pw.Widget> _qrWithLabel(
  List<String> codes,
  int index,
  int slot,
  pw.TextStyle style,
) {
  final origin = QrPageLayout.qrOrigin(slot);
  final size = QrPageLayout.qrSize;
  final qr = buildAlphanumericQr(codes[index]);
  return [
    pw.Positioned(
      left: origin.x,
      top: origin.y,
      child: pw.SizedBox(
        width: size,
        height: size,
        child: pw.CustomPaint(
          size: PdfPoint(size, size),
          painter: (canvas, area) => _paintQr(canvas, area, qr),
        ),
      ),
    ),
    pw.Positioned(
      left: origin.x,
      top: origin.y + size + 2,
      child: pw.SizedBox(
        width: size,
        child: pw.Text(
          '${index + 1} / ${codes.length}',
          style: style,
          textAlign: pw.TextAlign.center,
        ),
      ),
    ),
  ];
}

/// Dibuja los módulos (con 4 módulos de zona de silencio) agrupando los
/// tramos horizontales para que el PDF sea liviano.
void _paintQr(PdfGraphics canvas, PdfPoint area, QrImage qr) {
  final n = qr.moduleCount;
  final m = area.x / (n + 8);
  canvas.setFillColor(PdfColors.black);
  for (var row = 0; row < n; row++) {
    var col = 0;
    while (col < n) {
      if (!qr.isDark(row, col)) {
        col++;
        continue;
      }
      final start = col;
      while (col < n && qr.isDark(row, col)) {
        col++;
      }
      // El origen de CustomPaint está abajo a la izquierda.
      canvas.drawRect(
        (start + 4) * m,
        area.y - (row + 5) * m,
        (col - start) * m,
        m,
      );
    }
  }
  canvas.fillPath();
}

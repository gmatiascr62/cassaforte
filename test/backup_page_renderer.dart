import 'dart:typed_data';

import 'package:cassaforte/src/backup/qr_codes.dart';
import 'package:cassaforte/src/backup/qr_image_reader.dart';
import 'package:cassaforte/src/backup/qr_page_layout.dart';

/// Dibuja las hojas tal como las rasteriza un visor de PDF: misma
/// disposición y mismo QR que el PDF real, a la resolución indicada.
List<GrayImage> renderPages(List<String> codes, {double dpi = 150}) {
  final scale = dpi / 72;
  final w = (QrPageLayout.pageWidth * scale).round();
  final h = (QrPageLayout.pageHeight * scale).round();
  final pages = <GrayImage>[];
  for (var page = 0; page < QrPageLayout.pageCount(codes.length); page++) {
    final px = Uint8List(w * h)..fillRange(0, w * h, 255);
    for (var slot = 0; slot < QrPageLayout.perPage; slot++) {
      final index = page * QrPageLayout.perPage + slot;
      if (index >= codes.length) break;
      final qr = buildAlphanumericQr(codes[index]);
      final o = QrPageLayout.qrOrigin(slot);
      final n = qr.moduleCount;
      final m = QrPageLayout.qrSize / (n + 8) * scale;
      final ox = o.x * scale + 4 * m;
      final oy = o.y * scale + 4 * m;
      for (var r = 0; r < n; r++) {
        for (var c = 0; c < n; c++) {
          if (!qr.isDark(r, c)) continue;
          final x0 = (ox + c * m).round(), x1 = (ox + (c + 1) * m).round();
          final y0 = (oy + r * m).round(), y1 = (oy + (r + 1) * m).round();
          for (var y = y0; y < y1; y++) {
            px.fillRange(y * w + x0, y * w + x1, 0);
          }
        }
      }
    }
    pages.add(GrayImage(w, h, px));
  }
  return pages;
}

/// Rectángulo en coordenadas relativas a la página (0..1, origen arriba a
/// la izquierda).
class NormRect {
  const NormRect(this.left, this.top, this.width, this.height);
  final double left;
  final double top;
  final double width;
  final double height;
}

/// Disposición de los códigos QR en las hojas A4 del PDF. La comparten el
/// generador del PDF y el lector, que recorta cada celda para leer los
/// códigos de forma fiable.
class QrPageLayout {
  /// A4 en puntos tipográficos (1/72 pulgadas).
  static const double pageWidth = 595.28;
  static const double pageHeight = 841.89;

  static const int columns = 2;
  static const int rows = 3;
  static const int perPage = columns * rows;

  static const double margin = 36;
  static const double headerHeight = 24;
  static const double labelHeight = 14;

  /// Espacio en blanco alrededor de cada QR, además de su zona de silencio.
  static const double gap = 14;

  static double get _cellWidth => (pageWidth - 2 * margin) / columns;
  static double get _cellHeight =>
      (pageHeight - 2 * margin - headerHeight) / rows;

  /// Lado del QR (incluida su zona de silencio) en puntos.
  static double get qrSize {
    final w = _cellWidth - gap;
    final h = _cellHeight - labelHeight - gap;
    return w < h ? w : h;
  }

  static int pageCount(int codes) => (codes + perPage - 1) ~/ perPage;

  /// Esquina superior izquierda del QR número [slot] (0..5) de una hoja, en
  /// puntos desde arriba a la izquierda.
  static ({double x, double y}) qrOrigin(int slot) {
    final col = slot % columns;
    final row = slot ~/ columns;
    final cellX = margin + col * _cellWidth;
    final cellY = margin + headerHeight + row * _cellHeight;
    return (
      x: cellX + (_cellWidth - qrSize) / 2,
      y: cellY + (_cellHeight - labelHeight - qrSize) / 2,
    );
  }

  /// Rectángulo exacto de cada QR (con su zona de silencio).
  static List<NormRect> qrRegions() => [
    for (var slot = 0; slot < perPage; slot++)
      () {
        final o = qrOrigin(slot);
        return NormRect(
          o.x / pageWidth,
          o.y / pageHeight,
          qrSize / pageWidth,
          qrSize / pageHeight,
        );
      }(),
  ];

  /// Celdas (con algo de margen extra) donde buscar cada QR al leer una hoja.
  static List<NormRect> readRegions() {
    const pad = 10.0;
    return [
      for (var slot = 0; slot < perPage; slot++)
        () {
          final o = qrOrigin(slot);
          double clampX(double v) => v.clamp(0, pageWidth);
          double clampY(double v) => v.clamp(0, pageHeight);
          final l = clampX(o.x - pad);
          final t = clampY(o.y - pad);
          final r = clampX(o.x + qrSize + pad);
          final b = clampY(o.y + qrSize + pad);
          return NormRect(
            l / pageWidth,
            t / pageHeight,
            (r - l) / pageWidth,
            (b - t) / pageHeight,
          );
        }(),
    ];
  }
}

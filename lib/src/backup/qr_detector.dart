// Usa piezas internas de zxing2 (versión fijada en pubspec.yaml).
// ignore_for_file: implementation_imports
import 'dart:math' as math;

import 'package:zxing2/qrcode.dart';
import 'package:zxing2/src/common/bit_matrix.dart';
import 'package:zxing2/src/common/grid_sampler.dart';
import 'package:zxing2/src/common/perspective_transform.dart';
import 'package:zxing2/src/qrcode/decoder/decoder.dart';
import 'package:zxing2/src/qrcode/decoder/version.dart';
import 'package:zxing2/src/qrcode/detector/alignment_pattern_finder.dart';
import 'package:zxing2/src/qrcode/detector/detector.dart';
import 'package:zxing2/src/qrcode/detector/finder_pattern.dart';
import 'package:zxing2/src/qrcode/detector/finder_pattern_finder.dart';
import 'package:zxing2/src/qrcode/detector/finder_pattern_info.dart';

/// Detector de QR para fotos de la cámara, armado sobre zxing2.
///
/// zxing2 (como ZXing en Java) falla con frecuencia en fotos inclinadas,
/// que son lo normal al apuntar el teléfono a una hoja:
///
/// 1. Para elegir las tres esquinas compara triángulos de candidatos por su
///    deformación en píxeles, así que un triángulo diminuto de ruido gana al
///    triángulo real, grande y algo deformado. Aquí la deformación se mide
///    en proporción al tamaño, se descartan los candidatos vistos una sola
///    vez (si hay otros) y se prueban varios triángulos.
/// 2. Calcula dónde está el patrón de alineación de abajo a la derecha como
///    si el código fuera un paralelogramo. Con la hoja en perspectiva (un
///    trapecio) el error llega a varios módulos y toma otro patrón de
///    alineación interior, con lo que la cuadrícula sale mal. Aquí se
///    buscan patrones de alineación cerca de varias posiciones y se prueba a
///    qué posición de la cuadrícula corresponde cada uno.
///
/// Cada hipótesis se valida decodificando: la corrección de errores
/// (Reed-Solomon) del QR rechaza las cuadrículas equivocadas.
class QrDetector {
  QrDetector._();

  static const int _maxCenters = 30;
  static const int _maxTriples = 4;
  static const int _maxHypotheses = 10;

  /// Detecta y decodifica un QR en [bits]. Lanza [ReaderException] si no
  /// lo consigue.
  static ({String text, List<ResultPoint> points}) decode(
    BitMatrix bits,
    DecodeHints hints,
  ) {
    final finder = FinderPatternFinder(bits);
    ReaderException lastError;
    try {
      // Primero, las esquinas que elige zxing2: así se lee todo lo que ya
      // leía zxing2 sin correcciones.
      return _decodeWithFinders(bits, finder.find(hints), hints);
    } on ReaderException catch (e) {
      // Se usan igualmente los candidatos encontrados.
      lastError = e;
    }
    var centers = finder.possibleCenters;
    final confirmed = [
      for (final c in centers)
        if (c.count >= 2) c,
    ];
    if (confirmed.length >= 3) centers = confirmed;
    for (final triple in _bestTriples(centers)) {
      final ordered = List<FinderPattern>.of(triple);
      ResultPoint.orderBestPatterns(ordered);
      try {
        return _decodeWithFinders(bits, FinderPatternInfo(ordered), hints);
      } on ReaderException catch (e) {
        lastError = e;
      }
    }
    throw lastError;
  }

  /// Los triángulos de candidatos más parecidos a un triángulo rectángulo
  /// isósceles (como las tres esquinas de un QR), del mejor al peor.
  static List<List<FinderPattern>> _bestTriples(List<FinderPattern> all) {
    // Con muchísimos candidatos (ruido), se quedan los más confirmados.
    final centers = List<FinderPattern>.of(all)
      ..sort((a, b) => b.count.compareTo(a.count));
    if (centers.length > _maxCenters) centers.length = _maxCenters;
    final scored = <(int, double, List<FinderPattern>)>[];
    for (var i = 0; i < centers.length - 2; i++) {
      for (var j = i + 1; j < centers.length - 1; j++) {
        for (var k = j + 1; k < centers.length; k++) {
          final t = [centers[i], centers[j], centers[k]];
          final sizes = t.map((p) => p.estimatedModuleSize).toList()..sort();
          if (sizes[2] > sizes[0] * 1.4) continue;
          final sides = [_d2(t[0], t[1]), _d2(t[1], t[2]), _d2(t[0], t[2])]
            ..sort();
          final a = sides[0], b = sides[1], c = sides[2];
          // Demasiado cerca para ser esquinas del mismo QR (menos de 14
          // módulos entre centros; un QR versión 1 tiene 14).
          final minSide = 14 * sizes[0];
          if (a < minSide * minSide) continue;
          final distortion = ((c - 2 * b).abs() + (c - 2 * a).abs()) / c;
          // A igual deformación (en tramos de 0,05), primero el triángulo
          // más chico: en una hoja con varios códigos alineados, las
          // esquinas de códigos vecinos también forman triángulos casi
          // perfectos, pero más grandes.
          scored.add(((distortion / 0.05).floor(), c, t));
        }
      }
    }
    scored.sort((p, q) {
      final byDistortion = p.$1.compareTo(q.$1);
      return byDistortion != 0 ? byDistortion : p.$2.compareTo(q.$2);
    });
    return [for (final s in scored.take(_maxTriples)) s.$3];
  }

  static double _d2(ResultPoint p, ResultPoint q) {
    final dx = p.x - q.x, dy = p.y - q.y;
    return dx * dx + dy * dy;
  }

  static ({String text, List<ResultPoint> points}) _decodeWithFinders(
    BitMatrix bits,
    FinderPatternInfo info,
    DecodeHints hints,
  ) {
    final tl = info.topLeft, tr = info.topRight, bl = info.bottomLeft;
    final detector = Detector(bits);
    final moduleSize = detector.calculateModuleSize(tl, tr, bl);
    if (moduleSize < 1.0) throw NotFoundException();

    ReaderException? lastError;
    // 1) Lo mismo que zxing2.
    try {
      final r = detector.processFinderPatternInfo(info);
      final decoded = Decoder().decode(r.bits, hints: hints);
      return (text: decoded.text, points: r.points);
    } on ReaderException catch (e) {
      lastError = e;
    }

    // 2) El tamaño estimado (en módulos) puede fallar por algunos módulos
    // con la perspectiva: se prueban los tamaños válidos más cercanos.
    for (final dim in _dimensions(tl, tr, bl, moduleSize)) {
      try {
        return _decodeWithDimension(bits, info, moduleSize, dim, hints);
      } on ReaderException catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? NotFoundException();
  }

  static ({String text, List<ResultPoint> points}) _decodeWithDimension(
    BitMatrix bits,
    FinderPatternInfo info,
    double moduleSize,
    int dim,
    DecodeHints hints,
  ) {
    final tl = info.topLeft, tr = info.topRight, bl = info.bottomLeft;
    final version = Version.getProvisionalVersionForDimension(dim);

    ({String text, List<ResultPoint> points}) attempt(
      ResultPoint? ref,
      double refX,
      double refY,
    ) {
      final far = dim - 3.5;
      final transform = PerspectiveTransform.quadrilateralToQuadrilateral(
        3.5,
        3.5,
        far,
        3.5,
        refX,
        refY,
        3.5,
        far,
        tl.x,
        tl.y,
        tr.x,
        tr.y,
        ref?.x ?? (tr.x - tl.x + bl.x),
        ref?.y ?? (tr.y - tl.y + bl.y),
        bl.x,
        bl.y,
      );
      final BitMatrix grid;
      try {
        grid = GridSampler.gridSampler.sampleGridTransform(
          bits,
          dim,
          dim,
          transform,
        );
      } on UnsupportedError {
        // Transformación degenerada (puntos casi alineados): da NaN.
        throw NotFoundException();
      }
      final decoded = Decoder().decode(grid, hints: hints);
      return (text: decoded.text, points: [bl, tl, tr, ?ref]);
    }

    ReaderException? lastError;
    // Hipótesis con los patrones de alineación encontrados cerca.
    final centersList = version.alignmentPatternCenters;
    if (centersList.isNotEmpty) {
      final first = centersList.first, last = centersList.last;
      // Posiciones de la cuadrícula del lado de abajo a la derecha: con las
      // del otro lado la transformación queda mal condicionada (o es
      // degenerada sobre la diagonal entre las esquinas).
      final grid = <(int, int)>[
        for (final cy in centersList)
          for (final cx in centersList)
            if (!(cx == first && cy == first) &&
                !(cx == first && cy == last) &&
                !(cx == last && cy == first) &&
                cx + cy + 1 > dim * 1.2)
              (cx, cy),
      ]..sort((a, b) => (b.$1 + b.$2).compareTo(a.$1 + a.$2));

      // Posición estimada (como paralelogramo) de una celda.
      ({double x, double y}) estimate(double u, double v) {
        final s = (u - 3.5) / (dim - 7), t = (v - 3.5) / (dim - 7);
        return (
          x: tl.x + s * (tr.x - tl.x) + t * (bl.x - tl.x),
          y: tl.y + s * (tr.y - tl.y) + t * (bl.y - tl.y),
        );
      }

      // El buscador de zxing2 mide tramos horizontales y verticales: con el
      // código girado, un módulo se ve más largo en esas direcciones (hasta
      // 1,41 veces a 45°).
      final angle = math.atan2(tr.y - tl.y, tr.x - tl.x);
      final apparent =
          moduleSize / math.max(math.cos(angle).abs(), math.sin(angle).abs());

      final found = <ResultPoint>[];
      for (final g in grid.take(3)) {
        final e = estimate(g.$1 + 0.5, g.$2 + 0.5);
        for (final allowance in const [5.0, 12.0]) {
          final p = _findAlignment(bits, apparent, e.x, e.y, allowance);
          if (p != null &&
              found.every((q) => math.sqrt(_d2(p, q)) > 2 * moduleSize)) {
            found.add(p);
          }
        }
      }

      final hypotheses = <(double, ResultPoint, (int, int))>[];
      for (final p in found) {
        for (final g in grid) {
          final e = estimate(g.$1 + 0.5, g.$2 + 0.5);
          final dx = e.x - p.x, dy = e.y - p.y;
          final off = math.sqrt(dx * dx + dy * dy) / moduleSize;
          if (off < 20) hypotheses.add((off, p, g));
        }
      }
      hypotheses.sort((a, b) => a.$1.compareTo(b.$1));
      for (final h in hypotheses.take(_maxHypotheses)) {
        try {
          return attempt(h.$2, h.$3.$1 + 0.5, h.$3.$2 + 0.5);
        } on ReaderException catch (e) {
          lastError = e;
        }
      }
    }

    // Sin patrón de alineación (paralelogramo).
    try {
      return attempt(null, dim - 3.5, dim - 3.5);
    } on ReaderException catch (e) {
      throw lastError ?? e;
    }
  }

  static const int _maxDimensions = 6;

  /// Tamaños válidos (4k + 1 módulos) entre los que dan los dos lados del
  /// código, del más cercano al promedio al más lejano. En perspectiva un
  /// lado se ve más corto que el otro y el promedio puede errar por varios
  /// módulos.
  static List<int> _dimensions(
    ResultPoint tl,
    ResultPoint tr,
    ResultPoint bl,
    double moduleSize,
  ) {
    final a = ResultPoint.distance(tl, tr) / moduleSize + 7;
    final b = ResultPoint.distance(tl, bl) / moduleSize + 7;
    final mid = (a + b) / 2;
    final lo = (math.min(a, b) - 4).floor();
    final hi = (math.max(a, b) + 4).ceil();
    final dims = [
      for (var d = 21; d <= 177; d += 4)
        if (d >= lo && d <= hi) d,
    ]..sort((x, y) => (x - mid).abs().compareTo((y - mid).abs()));
    return dims.take(_maxDimensions).toList();
  }

  static ResultPoint? _findAlignment(
    BitMatrix bits,
    double moduleSize,
    double x,
    double y,
    double allowanceModules,
  ) {
    final allowance = (allowanceModules * moduleSize).toInt();
    final left = math.max(0, x.toInt() - allowance);
    final right = math.min(bits.width - 1, x.toInt() + allowance);
    final top = math.max(0, y.toInt() - allowance);
    final bottom = math.min(bits.height - 1, y.toInt() + allowance);
    if (right - left < moduleSize * 3 || bottom - top < moduleSize * 3) {
      return null;
    }
    try {
      return AlignmentPatternFinder(
        bits,
        left,
        top,
        right - left,
        bottom - top,
        moduleSize,
      ).find();
    } on NotFoundException {
      return null;
    }
  }
}

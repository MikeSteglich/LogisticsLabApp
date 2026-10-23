/// Logo of LogisticsLab Studio: a supplier and three customers on a map, connected by routes.
///
/// Drawn in Dart, so the same picture is the app icon (tool/make_icons_test.dart), the logo of the about dialog and
/// the mark in the header.
library;

import 'package:flutter/material.dart';

class Logo extends StatelessWidget {
  final double size;
  const Logo({super.key, this.size = 26});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: const LogoPainter(), isComplex: false);
}

class LogoPainter extends CustomPainter {
  /// part of the size around the tile - transparent (macOS icons have such a margin)
  final double margin;
  const LogoPainter({this.margin = 0});

  static const _top = Color(0xFF3E86EC);
  static const _bottom = Color(0xFF173F9E);
  static const _customer = Color(0xFF45C784);
  static const _supplier = Color(0xFFFFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final m = size.width * margin;
    final s = size.width - 2 * m;
    Offset p(double x, double y) => Offset(m + x * s, m + y * s);
    final tile = RRect.fromRectAndRadius(Rect.fromLTWH(m, m, s, s), Radius.circular(s * 0.225));

    // tile with a light gradient, a soft shadow for larger sizes
    if (margin > 0) {
      canvas.drawRRect(
        tile.shift(Offset(0, s * 0.012)),
        Paint()
          ..color = const Color(0x40000000)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.02),
      );
    }
    canvas.drawRRect(
      tile,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_top, _bottom],
        ).createShader(tile.outerRect),
    );
    canvas.save();
    canvas.clipRRect(tile);

    // the map: two faint roads
    final faint = Paint()
      ..color = const Color(0x24FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.035
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(p(-0.1, 0.46).dx, p(-0.1, 0.46).dy)
        ..cubicTo(
          p(0.25, 0.36).dx,
          p(0.25, 0.36).dy,
          p(0.55, 0.56).dx,
          p(0.55, 0.56).dy,
          p(1.1, 0.44).dx,
          p(1.1, 0.44).dy,
        ),
      faint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(p(0.56, -0.1).dx, p(0.56, -0.1).dy)
        ..cubicTo(p(0.48, 0.3).dx, p(0.48, 0.3).dy, p(0.62, 0.7).dx, p(0.62, 0.7).dy, p(0.5, 1.1).dx, p(0.5, 1.1).dy),
      faint,
    );

    // routes from the supplier to the customers
    final supplier = p(0.30, 0.68);
    final customers = [p(0.30, 0.28), p(0.72, 0.30), p(0.76, 0.70)];
    final controls = [p(0.20, 0.47), p(0.42, 0.40), p(0.53, 0.78)];
    final route = Paint()
      ..color = const Color(0xF2FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.055
      ..strokeCap = StrokeCap.round;
    for (final (i, c) in customers.indexed) {
      canvas.drawPath(
        Path()
          ..moveTo(supplier.dx, supplier.dy)
          ..quadraticBezierTo(controls[i].dx, controls[i].dy, c.dx, c.dy),
        route,
      );
    }

    // customers: green with a white ring
    for (final c in customers) {
      canvas.drawCircle(c, s * 0.095, Paint()..color = Colors.white);
      canvas.drawCircle(c, s * 0.068, Paint()..color = _customer);
    }
    // supplier: white square
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: supplier, width: s * 0.22, height: s * 0.22),
        Radius.circular(s * 0.04),
      ),
      Paint()..color = _supplier,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: supplier, width: s * 0.11, height: s * 0.11),
        Radius.circular(s * 0.02),
      ),
      Paint()..color = _bottom,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(LogoPainter old) => old.margin != margin;
}

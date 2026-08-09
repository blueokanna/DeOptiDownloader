import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../rust/api/types.dart';

/// Paints a [QrMatrix] scaled to any rectangle.
///
/// Dark runs per row are batched into a single `Path` so a Version-40 symbol
/// renders in one draw call — fast enough to repaint every frame at 60 fps.
class QrPainter extends CustomPainter {
  QrPainter({
    required this.matrix,
    required this.dark,
    required this.light,
    this.quietZoneModules = 4,
    super.repaint,
  });

  final QrMatrix matrix;
  final Color dark;
  final Color light;
  final int quietZoneModules;

  @override
  void paint(Canvas canvas, Size size) {
    final w = matrix.width;
    if (w == 0) {
      return;
    }
    canvas.drawRect(Offset.zero & size, Paint()..color = light);

    final totalModules = w + quietZoneModules * 2;
    final cell = math.min(size.width, size.height) / totalModules;
    final qrExtent = totalModules * cell;
    final left = (size.width - qrExtent) / 2 + quietZoneModules * cell;
    final top = (size.height - qrExtent) / 2 + quietZoneModules * cell;
    final cells = matrix.cells;
    final path = Path();
    for (var y = 0; y < w; y++) {
      var x = 0;
      final rowBase = y * w;
      while (x < w) {
        if (cells[rowBase + x] == 1) {
          var run = 1;
          while (x + run < w && cells[rowBase + x + run] == 1) {
            run++;
          }
          final moduleLeft = left + x * cell;
          final moduleTop = top + y * cell;
          // +0.6 overlaps one device pixel to hide sub-pixel seams.
          path.addRect(
            Rect.fromLTWH(moduleLeft, moduleTop, run * cell + 0.6, cell + 0.6),
          );
          x += run;
        } else {
          x++;
        }
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = dark
        ..isAntiAlias = false,
    );
  }

  @override
  bool shouldRepaint(QrPainter oldDelegate) =>
      oldDelegate.matrix != matrix ||
      oldDelegate.dark != dark ||
      oldDelegate.light != light ||
      oldDelegate.quietZoneModules != quietZoneModules;
}

/// A full QR stream display: dark/light colors, a quiet-zone margin and the
/// latest matrix fed through a [ValueListenable] so only the painter repaints.
class QrDisplay extends StatelessWidget {
  const QrDisplay({
    super.key,
    required this.matrix,
    this.dark = Colors.black,
    this.light = Colors.white,
    this.quietZoneModules = 4,
  });

  final ValueListenable<QrMatrix?> matrix;
  final Color dark;
  final Color light;
  final int quietZoneModules;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<QrMatrix?>(
      valueListenable: matrix,
      builder: (context, value, _) {
        if (value == null) {
          return const SizedBox.shrink();
        }
        return Center(
          child: AspectRatio(
            aspectRatio: 1,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: QrPainter(
                  matrix: value,
                  dark: dark,
                  light: light,
                  quietZoneModules: quietZoneModules,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
      },
    );
  }
}

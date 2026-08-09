import 'dart:math' as math;
import 'dart:ui' as ui;

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
  }) : super(repaint: matrix);

  final ValueListenable<QrMatrix?> matrix;
  final Color dark;
  final Color light;
  final int quietZoneModules;

  @override
  void paint(Canvas canvas, Size size) {
    final value = matrix.value;
    if (value == null || value.width == 0) {
      return;
    }
    final w = value.width;
    canvas.drawRect(Offset.zero & size, Paint()..color = light);

    final totalModules = w + quietZoneModules * 2;
    final cell = math.min(size.width, size.height) / totalModules;
    final qrExtent = totalModules * cell;
    final left = (size.width - qrExtent) / 2 + quietZoneModules * cell;
    final top = (size.height - qrExtent) / 2 + quietZoneModules * cell;
    final cells = value.cells;
    final points = Float32List(cells.length * 2);
    var pointOffset = 0;
    for (var y = 0; y < w; y++) {
      final rowBase = y * w;
      for (var x = 0; x < w; x++) {
        if (cells[rowBase + x] == 1) {
          points[pointOffset++] = left + (x + 0.5) * cell;
          points[pointOffset++] = top + (y + 0.5) * cell;
        }
      }
    }
    canvas.drawRawPoints(
      ui.PointMode.points,
      Float32List.sublistView(points, 0, pointOffset),
      Paint()
        ..color = dark
        ..isAntiAlias = false
        ..strokeCap = StrokeCap.square
        ..strokeWidth = cell + 0.5,
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
    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: QrPainter(
              matrix: matrix,
              dark: dark,
              light: light,
              quietZoneModules: quietZoneModules,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

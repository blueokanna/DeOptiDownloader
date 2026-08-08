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
    super.repaint,
  });

  final QrMatrix matrix;
  final Color dark;
  final Color light;

  @override
  void paint(Canvas canvas, Size size) {
    final w = matrix.width;
    if (w == 0) {
      return;
    }
    canvas.drawRect(Offset.zero & size, Paint()..color = light);

    final cell = size.width / w;
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
          final left = x * cell;
          final top = y * cell;
          // +0.6 overlaps one device pixel to hide sub-pixel seams.
          path.addRect(Rect.fromLTWH(left, top, run * cell + 0.6, cell + 0.6));
          x += run;
        } else {
          x++;
        }
      }
    }
    canvas.drawPath(path, Paint()..color = dark);
  }

  @override
  bool shouldRepaint(QrPainter oldDelegate) =>
      oldDelegate.matrix != matrix ||
      oldDelegate.dark != dark ||
      oldDelegate.light != light;
}

/// A full QR stream display: dark/light colors, a quiet-zone margin and the
/// latest matrix fed through a [ValueListenable] so only the painter repaints.
class QrDisplay extends StatelessWidget {
  const QrDisplay({
    super.key,
    required this.matrix,
    this.dark = Colors.black,
    this.light = Colors.white,
    this.margin = 16,
  });

  final ValueListenable<QrMatrix?> matrix;
  final Color dark;
  final Color light;
  final double margin;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<QrMatrix?>(
      valueListenable: matrix,
      builder: (context, value, _) {
        if (value == null) {
          return const SizedBox.shrink();
        }
        return RepaintBoundary(
          child: CustomPaint(
            painter: QrPainter(matrix: value, dark: dark, light: light),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }
}

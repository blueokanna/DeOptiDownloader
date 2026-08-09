import 'dart:typed_data';

import 'package:camera/camera.dart';

import 'luma_frame.dart';

/// Converts camera plugin frames into the tightly packed luma plane consumed
/// by the Rust QR decoder. Android commonly supplies YUV420 while Apple and
/// Windows camera backends commonly supply BGRA8888.
LumaFrame? cameraImageToLuma(CameraImage image, DateTime timestamp) {
  if (image.planes.isEmpty || image.width <= 0 || image.height <= 0) {
    return null;
  }

  switch (image.format.group) {
    case ImageFormatGroup.yuv420:
    case ImageFormatGroup.nv21:
      return _lumaPlane(image, timestamp);
    case ImageFormatGroup.bgra8888:
      return _bgraToLuma(image, timestamp);
    case ImageFormatGroup.jpeg:
    case ImageFormatGroup.unknown:
      return null;
  }
}

LumaFrame? _lumaPlane(CameraImage image, DateTime timestamp) {
  final plane = image.planes.first;
  final width = image.width;
  final height = image.height;
  final rowStride = plane.bytesPerRow;
  final pixelStride = plane.bytesPerPixel ?? 1;
  if (rowStride <= 0 || pixelStride <= 0) {
    return null;
  }

  final requiredBytes =
      (height - 1) * rowStride + (width - 1) * pixelStride + 1;
  if (plane.bytes.length < requiredBytes) {
    return null;
  }

  final gray = Uint8List(width * height);
  if (pixelStride == 1 && rowStride == width) {
    gray.setRange(0, gray.length, plane.bytes);
  } else {
    for (var y = 0; y < height; y++) {
      final row = y * rowStride;
      final outputRow = y * width;
      for (var x = 0; x < width; x++) {
        gray[outputRow + x] = plane.bytes[row + x * pixelStride];
      }
    }
  }
  return LumaFrame(
    data: gray,
    width: width,
    height: height,
    timestamp: timestamp,
  );
}

LumaFrame? _bgraToLuma(CameraImage image, DateTime timestamp) {
  final plane = image.planes.first;
  final width = image.width;
  final height = image.height;
  final rowStride = plane.bytesPerRow;
  final pixelStride = plane.bytesPerPixel ?? 4;
  if (rowStride <= 0 || pixelStride < 4) {
    return null;
  }

  final requiredBytes =
      (height - 1) * rowStride + (width - 1) * pixelStride + 4;
  if (plane.bytes.length < requiredBytes) {
    return null;
  }

  final gray = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    final row = y * rowStride;
    final outputRow = y * width;
    for (var x = 0; x < width; x++) {
      final offset = row + x * pixelStride;
      final blue = plane.bytes[offset];
      final green = plane.bytes[offset + 1];
      final red = plane.bytes[offset + 2];
      gray[outputRow + x] = (77 * red + 150 * green + 29 * blue) >> 8;
    }
  }
  return LumaFrame(
    data: gray,
    width: width,
    height: height,
    timestamp: timestamp,
  );
}

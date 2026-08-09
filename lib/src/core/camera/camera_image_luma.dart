import 'dart:typed_data';

import 'package:camera/camera.dart';

import 'luma_frame.dart';

/// Longest side (in pixels) of the luma frame handed to the Rust decoder.
///
/// Camera sensors routinely deliver 1080p/4K, but the Rust scanner bounds
/// itself to [`DEFAULT_SCAN_DIM`] (~1280px) anyway. Decimating here — before
/// the `Uint8List` is built and shipped across the FFI boundary — cuts the
/// per-frame memory traffic by an order of magnitude (e.g. a 4K frame goes
/// from 8 MB to ~1.3 MB). This is the receiver's dominant cost on high-end
/// devices, so it lives as close to the camera as possible.
const int kMaxLumaSide = 1280;

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

  // Decimate so the larger side stays <= kMaxLumaSide (keeps aspect ratio).
  final step = width > kMaxLumaSide ? (width / kMaxLumaSide).ceil() : 1;
  final outWidth = (width / step).ceil();
  final outHeight = (height / step).ceil();

  final gray = Uint8List(outWidth * outHeight);
  if (step == 1 && pixelStride == 1 && rowStride == width) {
    gray.setRange(0, gray.length, plane.bytes);
  } else {
    final lastX = width - 1;
    final lastY = height - 1;
    for (var y = 0; y < outHeight; y++) {
      final row = (y * step).clamp(0, lastY) * rowStride;
      final outputRow = y * outWidth;
      for (var x = 0; x < outWidth; x++) {
        gray[outputRow + x] = plane.bytes[row + (x * step).clamp(0, lastX) * pixelStride];
      }
    }
  }
  return LumaFrame(
    data: gray,
    width: outWidth,
    height: outHeight,
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

  // Decimate so the larger side stays <= kMaxLumaSide (keeps aspect ratio).
  final step = width > kMaxLumaSide ? (width / kMaxLumaSide).ceil() : 1;
  final outWidth = (width / step).ceil();
  final outHeight = (height / step).ceil();

  final gray = Uint8List(outWidth * outHeight);
  final lastX = width - 1;
  final lastY = height - 1;
  for (var y = 0; y < outHeight; y++) {
    final row = (y * step).clamp(0, lastY) * rowStride;
    final outputRow = y * outWidth;
    for (var x = 0; x < outWidth; x++) {
      final offset = row + (x * step).clamp(0, lastX) * pixelStride;
      final blue = plane.bytes[offset];
      final green = plane.bytes[offset + 1];
      final red = plane.bytes[offset + 2];
      gray[outputRow + x] = (77 * red + 150 * green + 29 * blue) >> 8;
    }
  }
  return LumaFrame(
    data: gray,
    width: outWidth,
    height: outHeight,
    timestamp: timestamp,
  );
}

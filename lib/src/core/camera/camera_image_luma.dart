import 'package:camera/camera.dart';

import 'luma_frame.dart';

/// Longest side (in pixels) of the luma frame handed to the Rust decoder.
///
/// This is the scan-space bound consumed by the Rust worker: it converts the
/// raw camera plane to tight grayscale and box-downscales to `<= kMaxLumaSide`
/// with SIMD, in the same pass that decodes the QR. Camera sensors routinely
/// deliver 1080p/4K, so keeping the bound here — instead of decimating in a
/// Dart per-pixel loop — cuts both the Dart-side CPU and the per-frame memory
/// traffic by an order of magnitude (e.g. a 4K frame goes from 8 MB to
/// ~1.3 MB of scan data).
const int kMaxLumaSide = 1280;

/// Wraps a camera plugin frame as a raw [LumaFrame] for the Rust decoder.
///
/// No pixel work happens here: YUV420/NV21 frames forward their Y plane
/// untouched (with row/pixel strides), and BGRA8888 frames forward the raw
/// row. The scan conversion — luma math, padding strip, box downscale — runs
/// in the Rust worker with arch-dispatched SIMD.
LumaFrame? cameraImageToLuma(CameraImage image, DateTime timestamp) {
  if (image.planes.isEmpty || image.width <= 0 || image.height <= 0) {
    return null;
  }

  final plane = image.planes.first;
  switch (image.format.group) {
    case ImageFormatGroup.yuv420:
    case ImageFormatGroup.nv21:
      return LumaFrame(
        data: plane.bytes,
        width: image.width,
        height: image.height,
        timestamp: timestamp,
        format: LumaFormat.yplane,
        rowStride: plane.bytesPerRow,
        pixelStride: plane.bytesPerPixel ?? 1,
      );
    case ImageFormatGroup.bgra8888:
      return LumaFrame(
        data: plane.bytes,
        width: image.width,
        height: image.height,
        timestamp: timestamp,
        format: LumaFormat.bgra,
        rowStride: plane.bytesPerRow,
        pixelStride: plane.bytesPerPixel ?? 4,
      );
    case ImageFormatGroup.jpeg:
    case ImageFormatGroup.unknown:
      return null;
  }
}

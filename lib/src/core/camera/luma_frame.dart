import 'dart:typed_data';

/// How [LumaFrame.data] is packed. The receiver routes each format to the
/// matching Rust decode entry point, so the scan conversion (colour math,
/// padding strip, box downscale) happens inside the Rust worker with SIMD
/// instead of a Dart per-pixel loop.
enum LumaFormat {
  /// Raw YUV Y plane (Android / iOS / HarmonyOS): luma already, but the row
  /// may be padded and (rarely) interleaved at [LumaFrame.pixelStride].
  yplane,

  /// Raw BGRA8888 (Windows / macOS fallback): must be converted to luma.
  bgra,

  /// Tight row-major grayscale (already converted by the caller).
  gray,

  /// Tight row-major RGBA (web canvas path).
  rgba,
}

/// One raw camera frame for the Rust QR decoder.
///
/// [data] is the *raw* plane / buffer the camera delivered — padding is NOT
/// stripped in Dart. [width] / [height] are the logical image dimensions;
/// [rowStride] / [pixelStride] describe the packing and are honoured by the
/// Rust scan converter. Web frames are tight (`rowStride == 0`).
class LumaFrame {
  const LumaFrame({
    required this.data,
    required this.width,
    required this.height,
    required this.timestamp,
    required this.format,
    this.rowStride = 0,
    this.pixelStride = 1,
  });

  final Uint8List data;
  final int width;
  final int height;
  final DateTime timestamp;
  final LumaFormat format;

  /// Bytes per source row (0 for tight buffers).
  final int rowStride;

  /// Bytes between two horizontally adjacent luma samples (1 for planar Y).
  final int pixelStride;
}

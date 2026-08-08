import 'dart:typed_data';

/// One raw camera frame ready for the Rust QR decoder.
///
/// [data] is either tight row-major grayscale (`rgba == false`) or tight
/// row-major RGBA (`rgba == true`); the decoder picks the matching bridge
/// call. Native cameras deliver the Y plane directly (cheap); the web path
/// delivers canvas RGBA pixels.
class LumaFrame {
  const LumaFrame({
    required this.data,
    required this.width,
    required this.height,
    required this.timestamp,
    this.rgba = false,
  });

  final Uint8List data;
  final int width;
  final int height;
  final DateTime timestamp;
  final bool rgba;
}

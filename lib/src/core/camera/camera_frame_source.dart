import 'dart:async';

import 'package:flutter/widgets.dart';

import 'luma_frame.dart';

/// Raised when a camera cannot be acquired (missing device / permission).
class CameraSourceException implements Exception {
  CameraSourceException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Abstraction over the camera backends (native plugin vs web getUserMedia).
///
/// Each implementation owns the camera lifecycle and yields a stream of
/// [LumaFrame]s for the decoder loop. The receive page only ever talks to
/// this interface, so adding a platform (e.g. HarmonyOS) is a single new
/// implementation plus a factory entry.
abstract class CameraFrameSource {
  /// Human-readable backend name for diagnostics.
  String get name;

  /// Acquires the camera and starts delivering frames.
  Future<void> initialize();

  /// The decoded frame stream (throttled by each backend).
  Stream<LumaFrame> get frames;

  /// The live preview widget to embed in the receive page.
  Widget buildPreview();

  /// Releases the camera and stops the stream.
  Future<void> dispose();
}

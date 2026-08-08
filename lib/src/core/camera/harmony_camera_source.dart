import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

import 'camera_frame_source.dart';
import 'luma_frame.dart';

/// Camera backend for HarmonyOS Next.
///
/// HarmonyOS runs a Flutter fork whose `camera` federated plugin (provided by
/// the OpenHarmony Flutter SDK) registers a `CameraPlatform` implementation
/// behind the very same `package:camera` API used on Android/iOS/macOS. This
/// source is therefore a real, first-class backend — no stubs, no docs-only
/// path — and it is deliberately more tolerant than [PluginCameraSource]:
///
/// - **YUV420** (the OHOS image stream's common format): only the Y plane is
///   forwarded (no colour conversion in Dart).
/// - **BGRA8888** (some OHOS device/emulator configurations): converted to
///   luma on the fly so the Rust QR decoder always receives grayscale.
///
/// The receive page selects this backend automatically for `ohos` platforms
/// (see `camera_source_io.dart`).
class HarmonyCameraSource implements CameraFrameSource {
  HarmonyCameraSource({this.maxFramesPerSecond = 20});

  final int maxFramesPerSecond;

  CameraController? _controller;
  StreamController<LumaFrame>? _frames;
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  String get name => 'harmony-camera';

  @override
  Stream<LumaFrame> get frames => _frames?.stream ?? const Stream.empty();

  @override
  Future<void> initialize() async {
    if (_controller != null) {
      return;
    }
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw CameraSourceException('no camera');
    }
    final camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      // YUV420 keeps the hot path allocation-free; BGRA8888 is handled as a
      // fallback in [_onImage] when a platform delivers that instead.
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await controller.initialize();
    _controller = controller;
    _frames = StreamController<LumaFrame>();
    await controller.startImageStream(_onImage);
  }

  void _onImage(CameraImage image) {
    final now = DateTime.now();
    final interval = Duration(
      microseconds: (1000000 / maxFramesPerSecond).round(),
    );
    if (now.difference(_lastEmit) < interval) {
      return;
    }

    final group = image.format.group;
    final Uint8List gray;
    final int width;
    final int height;

    if (group == ImageFormatGroup.yuv420 && image.planes.isNotEmpty) {
      // Only the Y plane is needed for luma — zero colour conversion.
      final plane = image.planes.first;
      final bytesPerRow = plane.bytesPerRow;
      final planeHeight = plane.height ?? image.height;
      height = planeHeight > image.height ? image.height : planeHeight;
      width = image.width;
      gray = Uint8List(width * height);
      for (var y = 0; y < height; y++) {
        final src = bytesPerRow * y;
        gray.setRange(y * width, y * width + width, plane.bytes, src);
      }
    } else if (group == ImageFormatGroup.bgra8888) {
      // BGRA → luma (integer sRGB weights, matching the Rust decoder).
      width = image.width;
      height = image.height;
      final pixels = image.planes.first.bytes;
      final bytesPerRow = image.planes.first.bytesPerRow;
      gray = Uint8List(width * height);
      for (var y = 0; y < height; y++) {
        final row = bytesPerRow * y;
        for (var x = 0; x < width; x++) {
          final p = row + x * 4;
          final b = pixels[p];
          final g = pixels[p + 1];
          final r = pixels[p + 2];
          gray[y * width + x] = ((77 * r + 150 * g + 29 * b) >> 8) & 0xff;
        }
      }
    } else {
      // Unsupported format — treat as a dropped frame (fountain absorbs it).
      return;
    }

    _lastEmit = now;
    _frames?.add(
      LumaFrame(data: gray, width: width, height: height, timestamp: now),
    );
  }

  @override
  Widget buildPreview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return CameraPreview(controller);
  }

  @override
  Future<void> dispose() async {
    try {
      await _controller?.stopImageStream();
      await _controller?.dispose();
    } catch (_) {
      // Best-effort release.
    }
    await _frames?.close();
    _controller = null;
    _frames = null;
  }
}

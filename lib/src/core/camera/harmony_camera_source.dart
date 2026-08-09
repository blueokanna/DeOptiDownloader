import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

import 'camera_image_luma.dart';
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
    final frames = _frames;
    if (frames == null || frames.isClosed || frames.isPaused) {
      return;
    }
    final now = DateTime.now();
    final interval = Duration(
      microseconds: (1000000 / maxFramesPerSecond).round(),
    );
    if (now.difference(_lastEmit) < interval) {
      return;
    }

    final frame = cameraImageToLuma(image, now);
    if (frame == null) {
      return;
    }

    _lastEmit = now;
    frames.add(frame);
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

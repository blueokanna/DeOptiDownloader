import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

import 'camera_image_luma.dart';
import 'camera_frame_source.dart';
import 'luma_frame.dart';

/// Camera backend built on the federated `camera` plugin
/// (Android / iOS / macOS / Windows). Frames are delivered as YUV420; only
/// the Y plane is forwarded, so no colour conversion ever happens in Dart.
class PluginCameraSource implements CameraFrameSource {
  PluginCameraSource({this.maxFramesPerSecond = 20});

  final int maxFramesPerSecond;
  CameraController? _controller;
  StreamController<LumaFrame>? _frames;
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  String get name => 'camera-plugin';

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
    final frame = cameraImageToLuma(image, now);
    if (frame == null) {
      return;
    }
    _lastEmit = now;
    _frames?.add(frame);
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
      // best-effort release
    }
    await _frames?.close();
    _controller = null;
    _frames = null;
  }
}

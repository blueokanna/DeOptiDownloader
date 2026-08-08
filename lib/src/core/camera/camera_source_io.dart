import 'dart:io' show Platform;

import 'camera_frame_source.dart';
import 'harmony_camera_source.dart';
import 'plugin_camera_source.dart';

/// Whether the runtime is HarmonyOS Next (the OpenHarmony Flutter fork reports
/// `ohos` as its operating system).
bool _isOhos() {
  try {
    return Platform.operatingSystem.toLowerCase() == 'ohos';
  } catch (_) {
    return false;
  }
}

/// Native (io) factory.
///
/// - HarmonyOS Next → [HarmonyCameraSource] (format-tolerant camera backend).
/// - Everything else → the federated `camera` plugin
///   (Android / iOS / macOS / Windows).
CameraFrameSource createCameraSource() =>
    _isOhos() ? HarmonyCameraSource() : PluginCameraSource();

import 'camera_frame_source.dart';
import 'camera_source_io.dart' if (dart.library.js_interop) 'camera_source_web.dart' as impl;

/// Creates the camera backend for the current platform.
///
/// Native → `camera` plugin; web → getUserMedia + canvas. To add a new
/// platform (e.g. HarmonyOS) implement [CameraFrameSource] and route it here.
CameraFrameSource createCameraSource() => impl.createCameraSource();

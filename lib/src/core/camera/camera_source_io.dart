import 'camera_frame_source.dart';
import 'plugin_camera_source.dart';

/// Native (io) factory: the federated `camera` plugin.
CameraFrameSource createCameraSource() => PluginCameraSource();

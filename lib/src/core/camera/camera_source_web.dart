import 'camera_frame_source.dart';
import 'web_camera_source.dart';

/// Web factory: getUserMedia + canvas capture.
CameraFrameSource createCameraSource() => WebCameraSource();

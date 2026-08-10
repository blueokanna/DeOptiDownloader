// Web-only camera backend: getUserMedia → <video> preview (HtmlElementView)
// → periodic canvas capture → RGBA frames for the Rust decoder.
//
// Uses `dart:html` because the platform-view factory must return a DOM
// element; this file is only ever compiled for the web target.
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

import 'camera_frame_source.dart';
import 'luma_frame.dart';

class WebCameraSource implements CameraFrameSource {
  // 20 fps matches the receiver's adaptive decode budget (20–40 fps): the
  // canvas capture is cheap, and the latest-wins slot absorbs any excess.
  WebCameraSource({this.captureFramesPerSecond = 20});

  final int captureFramesPerSecond;

  html.MediaStream? _stream;
  html.VideoElement? _video;
  html.CanvasElement? _canvas;
  html.CanvasRenderingContext2D? _ctx;
  StreamController<LumaFrame>? _frames;
  Timer? _timer;
  String? _viewId;

  @override
  String get name => 'web-getUserMedia';

  @override
  Stream<LumaFrame> get frames => _frames?.stream ?? const Stream.empty();

  @override
  Future<void> initialize() async {
    if (_video != null) {
      return;
    }
    final media = html.window.navigator.mediaDevices;
    if (media == null) {
      throw CameraSourceException('mediaDevices unavailable (non-HTTPS?)');
    }
    final stream = await media.getUserMedia({
      'video': {
        'facingMode': 'environment',
        'width': {'ideal': 1280},
        'height': {'ideal': 720},
      },
      'audio': false,
    });
    final video = html.VideoElement()
      ..autoplay = true
      ..muted = true
      ..setAttribute('playsinline', '')
      ..srcObject = stream
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.setProperty('object-fit', 'cover');
    await video.play();
    _stream = stream;
    _video = video;
    _frames = StreamController<LumaFrame>();
    _viewId = 'deopti-camera-${DateTime.now().microsecondsSinceEpoch}';
    ui_web.platformViewRegistry.registerViewFactory(
      _viewId!,
      (int id) => video,
    );
    final canvas = html.CanvasElement();
    _canvas = canvas;
    _ctx = canvas.context2D;
    final interval = Duration(
      milliseconds: (1000 / captureFramesPerSecond).round(),
    );
    _timer = Timer.periodic(interval, (_) => _capture());
  }

  void _capture() {
    final frames = _frames;
    if (frames == null || frames.isClosed || frames.isPaused) {
      return;
    }
    final video = _video;
    final ctx = _ctx;
    final canvas = _canvas;
    if (video == null || ctx == null || canvas == null) {
      return;
    }
    if (video.videoWidth == 0 || video.videoHeight == 0) {
      return; // stream not ready yet
    }
    final w = video.videoWidth;
    final h = video.videoHeight;
    canvas.width = w;
    canvas.height = h;
    ctx.drawImage(video, 0, 0);
    final rgba = ctx.getImageData(0, 0, w, h).data;
    final bytes = Uint8List.fromList(rgba);
    frames.add(
      LumaFrame(
        data: bytes,
        width: w,
        height: h,
        format: LumaFormat.rgba,
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Widget buildPreview() {
    final viewId = _viewId;
    if (viewId == null) {
      return const SizedBox.shrink();
    }
    return HtmlElementView(viewType: viewId, key: ValueKey(viewId));
  }

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    final video = _video;
    if (video != null) {
      video.pause();
      video.srcObject = null;
    }
    for (final track in (_stream?.getTracks() ?? <html.MediaStreamTrack>[])) {
      track.stop();
    }
    await _frames?.close();
    _frames = null;
    _video = null;
    _canvas = null;
    _stream = null;
  }
}

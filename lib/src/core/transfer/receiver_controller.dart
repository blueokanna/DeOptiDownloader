import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../rust/api/qr.dart' as qr;
import '../../rust/api/transfer.dart';
import '../../rust/api/types.dart';
import '../camera/camera_frame_source.dart';
import '../camera/luma_frame.dart';

/// Receive-side orchestration: camera frames → Rust QR decode → fountain
/// receiver → DCF3 unpack, plus progress / no-signal state for the UI.
///
/// Frames are decoded one at a time; while a decode is in flight, further
/// camera frames are dropped (the fountain absorbs the loss). The receiver
/// re-locks automatically when the sender restarts (handled in Rust).
class ReceiverController extends ChangeNotifier {
  ReceiverController({required this.session});

  final ReceiverSession session;

  /// Current stream/progress state (from `receiverPush`).
  ReceiverOutcome outcome = ReceiverOutcome(
    status: PushStatus.ignored,
    container: null,
    collected: 0,
    k: null,
    blockLen: null,
    totalLen: null,
    sessionId: null,
    mode: null,
    delivered: false,
  );

  CameraFrameSource? source;
  StreamSubscription<LumaFrame>? _sub;
  Timer? _signalTimer;

  bool _decoding = false;
  bool _disposed = false;
  int _generation = 0;
  DateTime _lastDecodeAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _startedAt = DateTime.now();
  DateTime? _lastSignalAt;

  int decodedFrames = 0;
  int acceptedFrames = 0;
  double decodeFps = 0;

  /// Completed transfer (unencrypted or after password).
  OpticalFileData? completed;
  bool passwordRequired = false;
  bool jrcRequired = false;
  String? error;

  /// Latest decoded session manifest (shown as the sender's setup QR). Lets
  /// the UI preview the file before the first data frame arrives.
  ManifestInfo? manifest;
  bool get hasManifest => manifest != null;

  Uint8List? _pendingContainer;
  bool _unpacking = false;

  bool get hasSignal =>
      manifest != null || acceptedFrames > 0 || outcome.sessionId != null;

  /// Whether the "no signal" hint should be shown (no lock for 4 seconds).
  bool get showNoSignal {
    if (completed != null || hasSignal) {
      return false;
    }
    final anchor = _lastSignalAt ?? _startedAt;
    return DateTime.now().difference(anchor) > const Duration(seconds: 4);
  }

  double get progress {
    final k = outcome.k;
    if (k == null || k == 0) {
      return 0;
    }
    return (outcome.collected / (k * 1.15)).clamp(0.0, 1.0);
  }

  /// Binds a camera source and starts consuming frames.
  Future<void> start(CameraFrameSource camera) async {
    source = camera;
    _startedAt = DateTime.now();
    try {
      await camera.initialize();
    } catch (_) {
      await camera.dispose();
      if (identical(source, camera)) {
        source = null;
      }
      rethrow;
    }
    _sub = camera.frames.listen(
      _onFrame,
      onError: (Object value, StackTrace stackTrace) {
        error = value.toString();
        notifyListeners();
      },
    );
    _signalTimer?.cancel();
    _signalTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!hasSignal && completed == null) {
        notifyListeners();
      }
    });
    notifyListeners();
  }

  Future<void> _onFrame(LumaFrame frame) async {
    // Frames are decimated to <=1280px and decoded coarse-to-fine, so the
    // analysis loop can run up to ~30 fps; slow decodes apply natural
    // backpressure because only one Rust worker request may be active.
    if (_decoding) {
      return;
    }
    final interval = const Duration(milliseconds: 33);
    if (frame.timestamp.difference(_lastDecodeAt) < interval) {
      return;
    }
    final subscription = _sub;
    final generation = _generation;
    subscription?.pause();
    _decoding = true;
    _lastDecodeAt = frame.timestamp;
    try {
      final Uint8List? bytes;
      if (frame.rgba) {
        bytes = await qr.qrDecodeRgba(
          rgba: frame.data,
          width: frame.width,
          height: frame.height,
        );
      } else {
        bytes = await qr.qrDecodeGray(
          gray: frame.data,
          width: frame.width,
          height: frame.height,
        );
      }
      if (_disposed || generation != _generation) {
        return;
      }
      if (bytes == null) {
        return;
      }
      decodedFrames++;
      // A session manifest (the sender's setup QR) previews the transfer but
      // is not a fountain frame — surface it and skip the receiver.
      final m = decodeManifestFfi(bytes: bytes);
      if (m != null) {
        manifest = m;
        notifyListeners();
        return;
      }
      final result = receiverPush(session: session, frameBytes: bytes);
      outcome = result;
      if (result.status == PushStatus.accepted) {
        acceptedFrames++;
        _lastSignalAt = DateTime.now();
        _updateFps();
      }
      if (result.status == PushStatus.complete && result.container != null) {
        acceptedFrames++;
        _lastSignalAt = DateTime.now();
        await _handleContainer(result.container!);
      }
      notifyListeners();
    } catch (e) {
      if (_disposed || generation != _generation) {
        return;
      }
      error = e.toString();
      notifyListeners();
    } finally {
      if (generation == _generation) {
        _decoding = false;
        if (!_disposed && identical(_sub, subscription)) {
          subscription?.resume();
        }
      }
    }
  }

  Future<void> _handleContainer(Uint8List container) async {
    if (_unpacking) {
      return;
    }
    _unpacking = true;
    try {
      // A JRC envelope begins with the "JRC\x01" magic, not the DCF3 magic.
      // Only the designated judge can recover it, so route to the judge flow.
      if (_isJrcEnvelope(container)) {
        jrcRequired = true;
        _pendingContainer = container;
        notifyListeners();
        return;
      }
      final file = unpackFileFfi(container: container);
      completed = file;
      _signalTimer?.cancel();
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('encrypt')) {
        // Authenticated container: prompt for the password.
        passwordRequired = true;
        _pendingContainer = container;
      } else {
        error = e.toString();
      }
    } finally {
      _unpacking = false;
    }
  }

  /// Whether [bytes] look like a serialized JRC envelope (`"JRC\x01"`).
  static bool _isJrcEnvelope(Uint8List bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0x4A &&
      bytes[1] == 0x52 &&
      bytes[2] == 0x43 &&
      bytes[3] == 0x01;

  /// Submits the password for an encrypted transfer; returns success.
  Future<bool> submitPassword(String password) async {
    if (_pendingContainer == null) {
      return false;
    }
    try {
      final file = unpackFileWithPasswordFfi(
        container: _pendingContainer!,
        password: password,
      );
      completed = file;
      _signalTimer?.cancel();
      passwordRequired = false;
      _pendingContainer = null;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Submits the judge secret key (hex) for a JRC transfer; returns success.
  Future<bool> submitJudgeKey(List<int> judgeSecretKey) async {
    if (_pendingContainer == null) {
      return false;
    }
    try {
      final file = unpackFileJrcFfi(
        envelope: _pendingContainer!,
        judgeSecretKey: judgeSecretKey,
      );
      completed = file;
      _signalTimer?.cancel();
      jrcRequired = false;
      _pendingContainer = null;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _updateFps() {
    final window = DateTime.now().difference(_startedAt);
    decodeFps = window.inMilliseconds == 0
        ? 0
        : decodedFrames / (window.inMilliseconds / 1000);
  }

  /// Stops the camera and resets receiver state for another transfer.
  Future<void> reset() async {
    _generation++;
    _decoding = false;
    await _sub?.cancel();
    _sub = null;
    _signalTimer?.cancel();
    _signalTimer = null;
    await source?.dispose();
    source = null;
    outcome = ReceiverOutcome(
      status: PushStatus.ignored,
      container: null,
      collected: 0,
      k: null,
      blockLen: null,
      totalLen: null,
      sessionId: null,
      mode: null,
      delivered: false,
    );
    decodedFrames = 0;
    acceptedFrames = 0;
    completed = null;
    passwordRequired = false;
    jrcRequired = false;
    error = null;
    manifest = null;
    _pendingContainer = null;
    _startedAt = DateTime.now();
    _lastSignalAt = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _sub?.cancel();
    _sub = null;
    _signalTimer?.cancel();
    source?.dispose();
    super.dispose();
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../rust/api/qr.dart' as qr;
import '../../rust/api/transfer.dart';
import '../../rust/api/types.dart';
import '../camera/camera_frame_source.dart';
import '../camera/camera_image_luma.dart';
import '../camera/luma_frame.dart';

/// A single-slot "latest wins" frame holder.
///
/// The camera listener only ever writes here (never decodes); the decode
/// worker takes the most recent frame when it is idle. A frame that arrives
/// while the worker is busy replaces the pending one — nothing ever queues,
/// so memory stays bounded and stale frames are dropped instead of copied.
class LatestFrameSlot {
  LumaFrame? _pending;

  bool get hasPending => _pending != null;

  /// Takes the latest frame, if any.
  LumaFrame? take() {
    final frame = _pending;
    _pending = null;
    return frame;
  }

  /// Stores the latest frame, replacing any older pending one.
  void put(LumaFrame frame) {
    _pending = frame;
  }

  void clear() {
    _pending = null;
  }
}

/// Receive-side orchestration: camera frames → Rust QR decode (ROI-tracked) →
/// protocol admission → fountain receiver → DCF3 unpack, plus progress /
/// no-signal state for the UI.
///
/// Pipeline (each stage is decoupled, per the receiver architecture guide):
/// ```
/// Camera listener ──put──▶ LatestFrameSlot (cap. 1, never queues)
///                                │ take (latest only)
///                                ▼
///                     QR worker: SIMD scan + ROI tracker + decode
///                                │ bytes
///                                ▼
///                     Protocol admission: magic/length → fountain | manifest
///                                │
///                                ▼
///                     Fountain receiver (incremental peel, sub-ms)
///                                │
///                                ▼
///                     UI telemetry (throttled) / file assembly
/// ```
/// The camera thread never decodes; the QR decode runs on an FRB worker; the
/// fountain peel is incremental and cheap; the UI is only notified at a
/// bounded rate unless the transfer completes or fails.
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

  final LatestFrameSlot _slot = LatestFrameSlot();
  QrTrackerState _tracker = QrTrackerState();
  bool _decoding = false;
  bool _disposed = false;
  DateTime _lastDecodeAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _startedAt = DateTime.now();
  DateTime? _lastSignalAt;
  DateTime _lastUiNotify = DateTime.fromMillisecondsSinceEpoch(0);

  /// Minimum wall-clock gap between two decode attempts. Camera frames can
  /// arrive at 30 fps but the receiver analysis target is ~12–20 fps: each
  /// symbol stays on screen ~125 ms, so decoding 20×/s already yields 2–3
  /// exposure-stable reads per symbol. The slot absorbs the excess frames.
  static const Duration kMinDecodeInterval = Duration(milliseconds: 50);

  /// UI notification budget: progress refreshes at ~5 Hz; terminal events
  /// (complete / error / auth prompt) always notify immediately.
  static const Duration kUiNotifyBudget = Duration(milliseconds: 200);

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
      // Camera thread: write-only to the slot, never decode.
      _slot.put,
      onError: (Object value, StackTrace stackTrace) {
        error = value.toString();
        _maybeNotify(force: true);
      },
    );
    unawaited(_pump());
    _signalTimer?.cancel();
    _signalTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!hasSignal && completed == null) {
        _maybeNotify(force: true);
      }
    });
    _maybeNotify(force: true);
  }

  /// Decode worker: takes the latest frame, decodes it (Rust worker thread,
  /// ROI-tracked), admits the payload and folds it into the fountain.
  Future<void> _pump() async {
    while (!_disposed) {
      if (_decoding) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
        continue;
      }
      // Honor the decode budget without dropping frames: wait for the
      // interval to elapse before taking the latest frame.
      final since = DateTime.now().difference(_lastDecodeAt);
      if (since < kMinDecodeInterval) {
        await Future<void>.delayed(kMinDecodeInterval - since);
        continue;
      }
      final frame = _slot.take();
      if (frame == null) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
        continue;
      }
      await _processFrame(frame);
    }
  }

  Future<void> _processFrame(LumaFrame frame) async {
    _decoding = true;
    _lastDecodeAt = frame.timestamp;
    try {
      final result = await _decodeTracked(frame);
      if (_disposed) {
        return;
      }
      _tracker = result.tracker;
      final bytes = result.bytes;
      if (bytes == null) {
        return; // no QR in this frame — erasure for the fountain
      }
      decodedFrames++;
      // Protocol admission runs before the fountain: fountain frames carry
      // the "D1 0F" magic, anything else is probed as a session manifest.
      // This gate also spares the fountain worker for garbage payloads.
      if (_isFountainFrame(bytes)) {
        await _pushFountain(bytes);
      } else {
        final m = decodeManifestFfi(bytes: bytes);
        if (m != null) {
          manifest = m;
          _lastSignalAt ??= DateTime.now();
          _maybeNotify(force: true);
        }
      }
    } catch (e) {
      if (_disposed) {
        return;
      }
      error = e.toString();
      _maybeNotify(force: true);
    } finally {
      _decoding = false;
    }
  }

  /// Routes the frame to the matching Rust decode entry point (SIMD scan
  /// conversion + ROI tracking happen inside the worker).
  Future<QrDecodeResult> _decodeTracked(LumaFrame f) {
    switch (f.format) {
      case LumaFormat.yplane:
        return qr.qrDecodeYplaneTracked(
          yPlane: f.data,
          width: f.width,
          height: f.height,
          rowStride: f.rowStride,
          pixelStride: f.pixelStride,
          maxScanDim: kMaxLumaSide,
          tracker: _tracker,
        );
      case LumaFormat.bgra:
        return qr.qrDecodeBgraTracked(
          bgra: f.data,
          width: f.width,
          height: f.height,
          rowStride: f.rowStride,
          maxScanDim: kMaxLumaSide,
          tracker: _tracker,
        );
      case LumaFormat.gray:
        return qr.qrDecodeGrayTracked(
          gray: f.data,
          width: f.width,
          height: f.height,
          maxScanDim: kMaxLumaSide,
          tracker: _tracker,
        );
      case LumaFormat.rgba:
        return qr.qrDecodeRgbaTracked(
          rgba: f.data,
          width: f.width,
          height: f.height,
          maxScanDim: kMaxLumaSide,
          tracker: _tracker,
        );
    }
  }

  /// Cheap admission gate: a protocol-v3 fountain frame starts with the
  /// "D1 0F" magic and is at least header + 1 payload byte long. Full
  /// integrity (frame tag, stream identity, dedup) is verified by the Rust
  /// receiver; this only avoids FFI crossings for obviously wrong payloads.
  static bool _isFountainFrame(Uint8List bytes) =>
      bytes.length > 25 && bytes[0] == 0xD1 && bytes[1] == 0x0F;

  Future<void> _pushFountain(Uint8List bytes) async {
    final result = receiverPush(session: session, frameBytes: bytes);
    outcome = result;
    switch (result.status) {
      case PushStatus.accepted:
        acceptedFrames++;
        _lastSignalAt = DateTime.now();
        _updateFps();
        _maybeNotify();
      case PushStatus.complete:
        if (result.container != null) {
          acceptedFrames++;
          _lastSignalAt = DateTime.now();
          await _handleContainer(result.container!);
          _maybeNotify(force: true);
        }
      case PushStatus.ignored:
        // Damaged / duplicate frame, or the transfer already completed — the
        // fountain absorbs it as an erasure. No error, no notification.
        break;
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
        _maybeNotify(force: true);
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
      _maybeNotify(force: true);
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
      _maybeNotify(force: true);
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

  /// Notifies the UI at a bounded rate; [force] bypasses the budget for
  /// terminal events so completion/errors/auth prompts appear immediately.
  void _maybeNotify({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastUiNotify) < kUiNotifyBudget) {
      return;
    }
    _lastUiNotify = now;
    notifyListeners();
  }

  /// Stops the camera and resets receiver state for another transfer.
  Future<void> reset() async {
    _decoding = false;
    _slot.clear();
    _tracker = QrTrackerState();
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
    _maybeNotify(force: true);
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _sub = null;
    _signalTimer?.cancel();
    source?.dispose();
    super.dispose();
  }
}

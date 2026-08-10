import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../rust/api/transfer.dart';
import '../../rust/api/types.dart';

/// Aggregated send statistics surfaced to the UI on a slow notifier.
class SenderStats {
  const SenderStats({
    this.framesSent = 0,
    this.measuredFps = 0.0,
    this.elapsed = Duration.zero,
    this.error,
  });

  final int framesSent;
  final double measuredFps;
  final Duration elapsed;
  final String? error;

  SenderStats copyWith({
    int? framesSent,
    double? measuredFps,
    Duration? elapsed,
    String? error,
  }) {
    return SenderStats(
      framesSent: framesSent ?? this.framesSent,
      measuredFps: measuredFps ?? this.measuredFps,
      elapsed: elapsed ?? this.elapsed,
      error: error ?? this.error,
    );
  }
}

/// Drives one sending session: emits fountain frames + their QR rendering at
/// a target *symbol* rate and publishes the latest matrix for the painter.
///
/// The screen refresh rate (fps) and the QR symbol rate are independent knobs:
/// the screen still repaints every frame, but a new QR symbol is produced only
/// every `ticksPerSymbol` display periods. Each symbol therefore stays on
/// screen for a dwell of ~`ticksPerSymbol / fps` seconds (≥ 1 display period),
/// giving a 5–10 fps receiver camera several exposure-stable reads per QR.
///
/// Threading model: a drift-corrected `Timer` enqueues ticks; a single async
/// drain loop calls the bridge once per tick (never concurrently), so a slow
/// encode cycle drops ticks instead of queueing them up.
class SenderController extends ChangeNotifier {
  SenderController({required this.session, required this.info});

  static const int defaultFps = 60;

  final SenderSession session;
  final SenderInfo info;

  /// Latest QR matrix; the painter listens to this (no widget rebuild).
  final ValueNotifier<QrMatrix?> matrix = ValueNotifier(null);

  /// Stats, refreshed ~2×/s so the status line does not churn.
  final ValueNotifier<SenderStats> stats = ValueNotifier(const SenderStats());

  int _fps = defaultFps;
  int get fps => _fps;

  /// New QR symbols per second (default 8 ⇒ ~125 ms dwell at any fps).
  double _symbolRate = defaultSymbolRate();
  double get symbolRate => _symbolRate;

  /// How many display periods each symbol is held (repeat count).
  int _dwellPeriods = 1;
  int get dwellPeriods => _dwellPeriods;

  bool _running = false;
  bool _paused = false;
  bool _inSetup = false;
  bool get running => _running;
  bool get paused => _paused;

  /// True while the session-manifest QR is shown and data frames have not
  /// started yet (the receiver is expected to preview the transfer first).
  bool get inSetup => _inSetup;

  int _framesSent = 0;
  int _pendingTicks = 0;
  int _ticksInSymbol = 0;
  bool _draining = false;
  bool _disposed = false;
  int _generation = 0;
  Timer? _timer;
  Timer? _setupTimer;
  final Stopwatch _clock = Stopwatch();
  final List<Duration> _frameTimestamps = [];
  DateTime? _lastStatsAt;

  /// Screen display periods per new QR symbol.
  ///
  /// The symbol must stay at least one display period and at least
  /// `fps / symbolRate` periods to hit the requested symbol rate.
  int get ticksPerSymbol =>
      math.max(_dwellPeriods, (_fps / _symbolRate).ceil().clamp(1, _fps));

  /// Sets the screen refresh rate; takes effect on the next schedule.
  void setFps(int fps) {
    _fps = fps.clamp(1, 120);
    if (_running) {
      _schedule();
    }
  }

  /// Sets the QR symbol rate (1..fps symbols per second). Independent of the
  /// screen refresh rate.
  void setSymbolRate(double rate) {
    _symbolRate = rate.clamp(1.0, _fps.toDouble());
    if (_running) {
      _schedule();
    }
  }

  /// Sets how many display periods each symbol stays on screen (1..8).
  /// Equivalent to "repeat the same seq for N display periods".
  void setDwellPeriods(int periods) {
    _dwellPeriods = periods.clamp(1, 8);
    if (_running) {
      _schedule();
    }
  }

  /// Shows [setupQr] (the session manifest) for [hold], then begins emitting
  /// fountain frames. During the hold the receiver can scan the setup QR and
  /// preview the transfer before data arrives.
  void startWithSetup(
    QrMatrix setupQr, {
    Duration hold = const Duration(seconds: 3),
  }) {
    if (_running) {
      return;
    }
    _generation++;
    _running = true;
    _inSetup = true;
    _paused = false;
    matrix.value = setupQr;
    notifyListeners();
    _setupTimer?.cancel();
    final generation = _generation;
    _setupTimer = Timer(hold, () {
      if (_disposed || !_running || generation != _generation) {
        return;
      }
      _setupTimer = null;
      _inSetup = false;
      _framesSent = 0;
      _ticksInSymbol = 0;
      _frameTimestamps.clear();
      _clock
        ..reset()
        ..start();
      _schedule();
      notifyListeners();
    });
  }

  void start() {
    if (_running) {
      return;
    }
    _generation++;
    _running = true;
    _paused = false;
    _framesSent = 0;
    _ticksInSymbol = 0;
    _frameTimestamps.clear();
    _clock
      ..reset()
      ..start();
    _schedule();
  }

  void pause() {
    _paused = true;
    _pendingTicks = 0;
    notifyListeners();
  }

  void resume() {
    _paused = false;
    if (_running) {
      _schedule();
    }
    notifyListeners();
  }

  void stop() {
    _generation++;
    _setupTimer?.cancel();
    _setupTimer = null;
    _timer?.cancel();
    _timer = null;
    _running = false;
    _paused = false;
    _inSetup = false;
    _pendingTicks = 0;
    _ticksInSymbol = 0;
    notifyListeners();
  }

  void _schedule() {
    _timer?.cancel();
    if (!_running || _paused) {
      return;
    }
    final interval = Duration(microseconds: (1000000 / _fps).round());
    _timer = Timer.periodic(interval, (_) {
      // Coalesce missed ticks. Fountain frames tolerate loss; queue growth
      // would increase latency and memory use without improving throughput.
      _pendingTicks = 1;
      unawaited(_drain());
    });
  }

  Future<void> _drain() async {
    if (_draining) {
      return;
    }
    _draining = true;
    try {
      while (_pendingTicks > 0 && _running && !_paused) {
        _pendingTicks--;
        await _emitOnce();
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _emitOnce() async {
    final generation = _generation;
    _ticksInSymbol++;
    if (_ticksInSymbol < ticksPerSymbol) {
      // Hold the current symbol for the remaining display periods so the
      // receiver gets several stable reads; only stats refresh.
      _maybePublishStats();
      return;
    }
    _ticksInSymbol = 0;
    try {
      final frame = await senderNextQr(session: session);
      if (_disposed || !_running || _paused || generation != _generation) {
        return;
      }
      _framesSent++;
      _frameTimestamps.add(_clock.elapsed);
      matrix.value = frame.qr;
      _maybePublishStats();
    } catch (e) {
      if (_disposed || generation != _generation) {
        return;
      }
      stats.value = stats.value.copyWith(error: e.toString());
      stop();
    }
  }

  void _maybePublishStats() {
    final elapsed = _clock.elapsed;
    // Keep the frame-time window to the last second for a stable fps reading.
    _frameTimestamps.removeWhere(
      (timestamp) => elapsed - timestamp > const Duration(seconds: 1),
    );
    final window = elapsed < const Duration(seconds: 1)
        ? elapsed
        : const Duration(seconds: 1);
    final measuredFps =
        _frameTimestamps.length /
        (window.inMicroseconds / Duration.microsecondsPerSecond).clamp(
          0.001,
          double.infinity,
        );
    final now = DateTime.now();
    if (_lastStatsAt == null ||
        now.difference(_lastStatsAt!) >= const Duration(milliseconds: 500)) {
      _lastStatsAt = now;
      stats.value = SenderStats(
        framesSent: _framesSent,
        measuredFps: measuredFps,
        elapsed: elapsed,
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _running = false;
    _pendingTicks = 0;
    _setupTimer?.cancel();
    _timer?.cancel();
    matrix.dispose();
    stats.dispose();
    super.dispose();
  }
}

import 'package:wakelock_plus/wakelock_plus.dart';

/// Screen keep-on, best-effort.
///
/// On Web the Wake Lock API can reject (no user activation, permission
/// denied, or a hidden page). A transfer must never be blocked — or aborted —
/// because the screen could not be kept on, so every call swallows failures.
abstract final class ScreenKeep {
  /// Try to keep the screen on while streaming/receiving.
  static Future<void> on() async {
    try {
      await WakelockPlus.enable();
    } catch (_) {
      // Best-effort only.
    }
  }

  /// Release the screen keep-on.
  static Future<void> off() async {
    try {
      await WakelockPlus.disable();
    } catch (_) {
      // Best-effort only.
    }
  }
}

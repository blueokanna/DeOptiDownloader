/// Shared formatting helpers.
library;

/// Renders a byte count in the tightest human unit (B / KB / MB).
String formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}

/// Renders a duration as `m:ss` (or `s.s` under a minute).
String formatElapsed(Duration d) {
  final total = d.inSeconds;
  if (total < 60) {
    return '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';
  }
  final m = total ~/ 60;
  final s = total % 60;
  return '${m}m ${s.toString().padLeft(2, '0')}s';
}

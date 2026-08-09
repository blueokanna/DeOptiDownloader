/// Shared helpers for JRC judge keys (raw 32-byte X25519 scalars ↔ hex).
library;

/// Encodes bytes as lowercase hex.
String bytesToHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Decodes a lowercase/uppercase hex string (even length) into bytes.
/// Returns `null` when the input is not valid hex.
List<int>? hexToBytes(String hex) {
  final h = hex.trim();
  if (h.isEmpty || h.length.isOdd) {
    return null;
  }
  final out = <int>[];
  for (var i = 0; i < h.length; i += 2) {
    final byte = int.tryParse(h.substring(i, i + 2), radix: 16);
    if (byte == null) {
      return null;
    }
    out.add(byte);
  }
  return out;
}

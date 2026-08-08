import 'dart:typed_data';

/// A payload the user chose to send: either a picked file or a text snippet
/// (a snippet is treated as a `text/plain` file named `snippet.txt`).
class PickedPayload {
  const PickedPayload({
    required this.name,
    required this.mimeType,
    required this.bytes,
    this.isSnippet = false,
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;
  final bool isSnippet;

  int get length => bytes.length;
}

// Web file service: file_picker for picking, anchor-download for saving,
// Web Share API for sharing with download fallback.
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';

import '../../rust/api/types.dart';
import '../transfer/payload.dart';
import 'file_service.dart';

class WebFileService implements FileService {
  @override
  Future<PickedPayload?> pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: true,
    );
    final file = result?.files.single;
    if (file == null || file.bytes == null) {
      return null;
    }
    final mimeType = lookupMimeType(file.name) ?? 'application/octet-stream';
    return PickedPayload(name: file.name, mimeType: mimeType, bytes: file.bytes!);
  }

  @override
  Future<String?> saveFile(OpticalFileData file) async {
    _downloadBytes(file.name, file.mimeType, file.bytes);
    return null; // browsers have no real path
  }

  void _downloadBytes(String name, String mimeType, Uint8List bytes) {
    final blob = html.Blob([bytes], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..download = name
      ..style.display = 'none';
    html.document.body?.children.add(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(url);
  }

  @override
  Future<void> shareFile(OpticalFileData file) async {
    try {
      await html.window.navigator.share({
        'files': <html.File>[
          html.File([file.bytes], file.name, {'type': file.mimeType}),
        ],
      });
    } catch (_) {
      _downloadBytes(file.name, file.mimeType, file.bytes);
    }
  }

  @override
  Future<void> shareText(String text) async {
    try {
      await html.window.navigator.share({'text': text});
      return;
    } catch (_) {
      // fall through to clipboard
    }
    await html.window.navigator.clipboard?.writeText(text);
  }
}

FileService createFileService() => WebFileService();

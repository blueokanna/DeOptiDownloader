import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../rust/api/types.dart';
import '../transfer/payload.dart';
import 'file_service.dart';

/// Native (io) file service: file_picker + disk + share sheet.
class IoFileService implements FileService {
  @override
  Future<PickedPayload?> pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: false,
    );
    final file = result?.files.single;
    if (file == null) {
      return null;
    }
    final bytes = await _readBytes(file);
    if (bytes == null) {
      return null;
    }
    final mimeType = lookupMimeType(file.name) ?? 'application/octet-stream';
    return PickedPayload(name: file.name, mimeType: mimeType, bytes: bytes);
  }

  Future<Uint8List?> _readBytes(PlatformFile file) async {
    if (file.bytes != null) {
      return file.bytes;
    }
    if (file.path != null) {
      return File(file.path!).readAsBytes();
    }
    return null;
  }

  @override
  Future<String?> saveFile(OpticalFileData file) async {
    final dir = await _downloadDir();
    final path = '${dir.path}${Platform.pathSeparator}${_safeName(file.name)}';
    await File(path).writeAsBytes(file.bytes, flush: true);
    return path;
  }

  Future<Directory> _downloadDir() async {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) {
      return downloads;
    }
    return getApplicationDocumentsDirectory();
  }

  @override
  Future<void> shareFile(OpticalFileData file) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}${Platform.pathSeparator}${_safeName(file.name)}';
    await File(path).writeAsBytes(file.bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path, mimeType: file.mimeType)]),
    );
  }

  @override
  Future<void> shareText(String text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  }

  String _safeName(String name) {
    final base = name.split(RegExp(r'[/\\]')).last;
    return base.isEmpty ? 'transfer.bin' : base;
  }
}

FileService createFileService() => IoFileService();

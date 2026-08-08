import '../../rust/api/types.dart';
import '../transfer/payload.dart';
import 'file_service_io.dart' if (dart.library.js_interop) 'file_service_web.dart' as impl;

/// Picks and saves files with platform-appropriate UX.
///
/// - Pick: `file_picker` everywhere.
/// - Save: real path on native, browser download on web.
/// - Share: native share sheet; Web Share API on web with download fallback.
abstract class FileService {
  /// Opens the system file picker; returns `null` when cancelled.
  Future<PickedPayload?> pickFile();

  /// Persists the received file and returns its path (null on web).
  Future<String?> saveFile(OpticalFileData file);

  /// Opens the platform share sheet for the file.
  Future<void> shareFile(OpticalFileData file);

  /// Shares plain text (snippet payloads).
  Future<void> shareText(String text);

  static FileService create() => impl.createFileService();
}

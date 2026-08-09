import 'wallpaper.dart';
import 'wallpaper_store_io.dart' if (dart.library.js_interop) 'wallpaper_store_web.dart' as impl;

/// Persists the current [WallpaperSpec].
///
/// On native platforms a custom image is copied into the application support
/// directory (shared_preferences only stores a small path string); on web the
/// bytes are kept as a base64 data URI in shared_preferences because there is
/// no filesystem.
abstract class WallpaperStore {
  Future<WallpaperSpec> load();

  Future<void> save(WallpaperSpec spec);

  /// Copies [bytes] into persistent storage and returns the stored reference
  /// (a file path on native, a `data:` URI on web).
  Future<String?> storeCustomImage(List<int> bytes);

  /// Deletes a previously stored custom image (best effort).
  Future<void> deleteCustomImage(WallpaperSpec spec);

  static WallpaperStore create() => impl.createWallpaperStore();
}

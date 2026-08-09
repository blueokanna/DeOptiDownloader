import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wallpaper.dart';
import 'wallpaper_store.dart';

const _kKind = 'wallpaper.kind';
const _kAsset = 'wallpaper.asset';
const _kImage = 'wallpaper.image';
const _kBlur = 'wallpaper.blur';
const _kCustomFile = 'wallpaper_custom.png';

/// Native implementation: custom image copied to the app support directory.
class IoWallpaperStore implements WallpaperStore {
  Future<File?> _customFile() async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$_kCustomFile');
    return file.existsSync() ? file : null;
  }

  @override
  Future<WallpaperSpec> load() async {
    final prefs = await SharedPreferences.getInstance();
    final kind = prefs.getString(_kKind);
    final blur = (prefs.getDouble(_kBlur) ?? 0).clamp(0.0, 24.0);
    switch (kind) {
      case 'builtin':
        final asset = prefs.getString(_kAsset);
        if (asset != null && kBuiltinWallpapers.contains(asset)) {
          return WallpaperSpec.builtin(asset, blur: blur);
        }
        return const WallpaperSpec.none();
      case 'custom':
        final file = await _customFile();
        if (file != null) {
          return WallpaperSpec.custom(file.path, blur: blur);
        }
        return const WallpaperSpec.none();
      default:
        return const WallpaperSpec.none();
    }
  }

  @override
  Future<void> save(WallpaperSpec spec) async {
    final prefs = await SharedPreferences.getInstance();
    switch (spec.kind) {
      case WallpaperKind.none:
        await prefs.remove(_kKind);
        await prefs.remove(_kAsset);
        await prefs.remove(_kImage);
        await prefs.remove(_kBlur);
      case WallpaperKind.builtin:
        await prefs.setString(_kKind, 'builtin');
        await prefs.setString(_kAsset, spec.assetId!);
        await prefs.remove(_kImage);
        await prefs.setDouble(_kBlur, spec.blur);
      case WallpaperKind.custom:
        await prefs.setString(_kKind, 'custom');
        await prefs.setString(_kImage, spec.imagePath ?? '');
        await prefs.setDouble(_kBlur, spec.blur);
    }
  }

  @override
  Future<String?> storeCustomImage(List<int> bytes) async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$_kCustomFile');
    await file.writeAsBytes(Uint8List.fromList(bytes), flush: true);
    return file.path;
  }

  @override
  Future<void> deleteCustomImage(WallpaperSpec spec) async {
    final file = await _customFile();
    try {
      await file?.delete();
    } catch (_) {
      // Best effort.
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kImage);
  }
}

WallpaperStore createWallpaperStore() => IoWallpaperStore();

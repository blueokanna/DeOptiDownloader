import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'wallpaper.dart';
import 'wallpaper_store.dart';

const _kKind = 'wallpaper.kind';
const _kAsset = 'wallpaper.asset';
const _kImage = 'wallpaper.image';
const _kBlur = 'wallpaper.blur';

/// Web implementation: everything lives in shared_preferences (a custom
/// image is kept as a base64 `data:` URI).
class WebWallpaperStore implements WallpaperStore {
  @override
  Future<WallpaperSpec> load() async {
    final prefs = await SharedPreferences.getInstance();
    final kind = prefs.getString(_kKind);
    final blur = (prefs.getDouble(_kBlur) ?? 0).clamp(0.0, 24.0);
    switch (kind) {
      case 'builtin':
        final asset = prefs.getString(_kAsset);
        if (asset != null && kBuiltinWallpapers.contains(asset)) {
          return WallpaperSpec.builtin(asset);
        }
        return const WallpaperSpec.none();
      case 'custom':
        final image = prefs.getString(_kImage);
        if (image != null && image.startsWith('data:')) {
          return WallpaperSpec.custom(image, blur: blur);
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
        await prefs.remove(_kBlur);
      case WallpaperKind.custom:
        await prefs.setString(_kKind, 'custom');
        await prefs.setString(_kImage, spec.imagePath ?? '');
        await prefs.setDouble(_kBlur, spec.blur);
    }
  }

  @override
  Future<String?> storeCustomImage(List<int> bytes) async {
    final mime = 'image/png';
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }

  @override
  Future<void> deleteCustomImage(WallpaperSpec spec) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kImage);
  }
}

WallpaperStore createWallpaperStore() => WebWallpaperStore();

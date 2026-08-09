import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme/app_themes.dart';
import 'theme/wallpaper.dart';
import 'theme/wallpaper_store.dart';

const _kThemeId = 'settings.themeId';
const _kThemeMode = 'settings.themeMode';
const _kLanguage = 'settings.language';
const _kJudgeSecretKey = 'settings.judgeSecretKey';

/// Persisted, app-wide user settings.
///
/// Exposes theme selection, theme mode, language override and the wallpaper.
/// All mutations write through to [SharedPreferences] immediately; widgets
/// react via `AnimatedBuilder`/`ListenableBuilder` on this controller.
class AppSettings extends ChangeNotifier {
  AppSettings._({
    required this.themeId,
    required this.themeMode,
    required this.languageCode,
    required this.wallpaper,
    required this.judgeSecretKey,
  });

  factory AppSettings.create() {
    return AppSettings._(
      themeId: ThemeId.indigoLight,
      themeMode: AppThemeMode.system,
      languageCode: null,
      wallpaper: const WallpaperSpec.none(),
      judgeSecretKey: null,
    );
  }

  ThemeId themeId;
  AppThemeMode themeMode;
  String? languageCode;
  WallpaperSpec wallpaper;
  String? judgeSecretKey;

  final WallpaperStore wallpaperStore = WallpaperStore.create();

  /// Loads persisted settings. Call once at startup, before runApp.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeId.fromId(prefs.getString(_kThemeId));
    if (theme != null) {
      themeId = theme;
    }
    final mode = prefs.getString(_kThemeMode);
    if (mode != null) {
      themeMode = AppThemeMode.values
          .firstWhere((m) => m.name == mode, orElse: () => AppThemeMode.system);
    }
    final lang = prefs.getString(_kLanguage);
    languageCode = (lang == null || lang.isEmpty || lang == 'system') ? null : lang;
    judgeSecretKey = prefs.getString(_kJudgeSecretKey);
    wallpaper = await wallpaperStore.load();
    notifyListeners();
  }

  /// Effective brightness for the current theme + mode.
  Brightness brightnessOf(Brightness platform) {
    final b = themeMode.resolve(platform);
    // AMOLED is a dark-only palette.
    if (themeId.amoled) {
      return Brightness.dark;
    }
    return b;
  }

  void setTheme(ThemeId id) {
    if (themeId == id) {
      return;
    }
    themeId = id;
    _persistTheme();
    notifyListeners();
  }

  void setThemeMode(AppThemeMode mode) {
    if (themeMode == mode) {
      return;
    }
    themeMode = mode;
    SharedPreferences.getInstance().then((p) => p.setString(_kThemeMode, mode.name));
    notifyListeners();
  }

  void setLanguage(String? code) {
    languageCode = (code == null || code.isEmpty) ? null : code;
    SharedPreferences.getInstance().then((p) {
      p.setString(_kLanguage, languageCode ?? 'system');
    });
    notifyListeners();
  }

  Future<void> setWallpaper(WallpaperSpec spec) async {
    wallpaper = spec;
    notifyListeners();
    await wallpaperStore.save(spec);
  }

  Future<void> setWallpaperBlur(double blur) async {
    wallpaper = wallpaper.copyWith(blur: blur);
    notifyListeners();
    await wallpaperStore.save(wallpaper);
  }

  /// Stores a custom image (bytes from the picker) and activates it.
  Future<String?> setCustomWallpaper(List<int> bytes) async {
    final stored = await wallpaperStore.storeCustomImage(bytes);
    if (stored == null) {
      return null;
    }
    wallpaper = WallpaperSpec.custom(stored, blur: 0);
    notifyListeners();
    await wallpaperStore.save(wallpaper);
    return stored;
  }

  Future<void> removeCustomWallpaper() async {
    await wallpaperStore.deleteCustomImage(wallpaper);
    if (wallpaper.kind == WallpaperKind.custom) {
      wallpaper = const WallpaperSpec.none();
      notifyListeners();
      await wallpaperStore.save(wallpaper);
    }
  }

  void setJudgeSecretKey(String? hex) {
    judgeSecretKey = (hex == null || hex.isEmpty) ? null : hex;
    SharedPreferences.getInstance().then((p) {
      if (judgeSecretKey == null) {
        p.remove(_kJudgeSecretKey);
      } else {
        p.setString(_kJudgeSecretKey, judgeSecretKey!);
      }
    });
    notifyListeners();
  }

  Future<void> restoreDefaults() async {
    themeId = ThemeId.indigoLight;
    themeMode = AppThemeMode.system;
    languageCode = null;
    judgeSecretKey = null;
    _persistTheme();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kThemeMode);
    await prefs.remove(_kLanguage);
    await prefs.remove(_kJudgeSecretKey);
    await wallpaperStore.save(const WallpaperSpec.none());
    wallpaper = const WallpaperSpec.none();
    notifyListeners();
  }

  void _persistTheme() {
    SharedPreferences.getInstance().then((p) => p.setString(_kThemeId, themeId.id));
  }
}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme/app_themes.dart';
import 'theme/wallpaper.dart';
import 'theme/wallpaper_store.dart';

const _kThemeId = 'settings.themeId';
const _kColorSpec = 'settings.colorSpec';
const _kColorStyle = 'settings.colorStyle';
const _kAmoled = 'settings.amoled';
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
    required this.colorSpec,
    required this.colorStyle,
    required this.amoled,
    required this.themeMode,
    required this.languageCode,
    required this.wallpaper,
    required this.judgeSecretKey,
  });

  factory AppSettings.create() {
    return AppSettings._(
      colorSpec: ColorSpec.indigo,
      colorStyle: ColorStyle.tonalSpot,
      amoled: false,
      themeMode: AppThemeMode.system,
      languageCode: null,
      wallpaper: const WallpaperSpec.none(),
      judgeSecretKey: null,
    );
  }

  ColorSpec colorSpec;
  ColorStyle colorStyle;
  bool amoled;
  AppThemeMode themeMode;
  String? languageCode;
  WallpaperSpec wallpaper;
  String? judgeSecretKey;

  final WallpaperStore wallpaperStore = WallpaperStore.create();

  /// Loads persisted settings. Call once at startup, before runApp.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final storedColorSpec = ColorSpec.fromId(prefs.getString(_kColorSpec));
    final storedColorStyle = ColorStyle.fromId(prefs.getString(_kColorStyle));
    colorSpec = storedColorSpec ?? colorSpec;
    colorStyle = storedColorStyle ?? colorStyle;
    amoled = prefs.getBool(_kAmoled) ?? amoled;
    if (storedColorSpec == null && storedColorStyle == null) {
      _migrateLegacyTheme(prefs.getString(_kThemeId));
    }
    final mode = prefs.getString(_kThemeMode);
    if (mode != null) {
      themeMode = AppThemeMode.values.firstWhere(
        (m) => m.name == mode,
        orElse: () => AppThemeMode.system,
      );
    }
    final lang = prefs.getString(_kLanguage);
    languageCode = (lang == null || lang.isEmpty || lang == 'system')
        ? null
        : lang;
    judgeSecretKey = prefs.getString(_kJudgeSecretKey);
    wallpaper = await wallpaperStore.load();
    notifyListeners();
  }

  /// Effective brightness for the current theme + mode.
  Brightness brightnessOf(Brightness platform) {
    final b = themeMode.resolve(platform);
    // AMOLED is a dark-only palette.
    if (amoled) {
      return Brightness.dark;
    }
    return b;
  }

  void setColorSpec(ColorSpec spec) {
    if (colorSpec == spec) {
      return;
    }
    colorSpec = spec;
    SharedPreferences.getInstance().then(
      (p) => p.setString(_kColorSpec, spec.id),
    );
    notifyListeners();
  }

  void setColorStyle(ColorStyle style) {
    if (colorStyle == style) {
      return;
    }
    colorStyle = style;
    SharedPreferences.getInstance().then(
      (p) => p.setString(_kColorStyle, style.id),
    );
    notifyListeners();
  }

  void setAmoled(bool value) {
    if (amoled == value) {
      return;
    }
    amoled = value;
    if (value) {
      themeMode = AppThemeMode.dark;
    }
    SharedPreferences.getInstance().then((p) async {
      await p.setBool(_kAmoled, value);
      if (value) {
        await p.setString(_kThemeMode, AppThemeMode.dark.name);
      }
    });
    notifyListeners();
  }

  void setThemeMode(AppThemeMode mode) {
    if (themeMode == mode) {
      return;
    }
    themeMode = mode;
    SharedPreferences.getInstance().then(
      (p) => p.setString(_kThemeMode, mode.name),
    );
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
    colorSpec = ColorSpec.indigo;
    colorStyle = ColorStyle.tonalSpot;
    amoled = false;
    themeMode = AppThemeMode.system;
    languageCode = null;
    judgeSecretKey = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kThemeId);
    await prefs.remove(_kColorSpec);
    await prefs.remove(_kColorStyle);
    await prefs.remove(_kAmoled);
    await prefs.remove(_kThemeMode);
    await prefs.remove(_kLanguage);
    await prefs.remove(_kJudgeSecretKey);
    await wallpaperStore.save(const WallpaperSpec.none());
    wallpaper = const WallpaperSpec.none();
    notifyListeners();
  }

  void _migrateLegacyTheme(String? id) {
    switch (id) {
      case 'amoled_dark':
        colorSpec = ColorSpec.indigo;
        colorStyle = ColorStyle.tonalSpot;
        amoled = true;
        themeMode = AppThemeMode.dark;
      case 'violet':
        colorSpec = ColorSpec.violet;
        colorStyle = ColorStyle.expressive;
      case 'midnight':
        colorSpec = ColorSpec.indigo;
        colorStyle = ColorStyle.fidelity;
      case 'sunset':
        colorSpec = ColorSpec.sunset;
        colorStyle = ColorStyle.vibrant;
      case 'monochrome':
        colorSpec = ColorSpec.neutral;
        colorStyle = ColorStyle.monochrome;
    }
  }
}

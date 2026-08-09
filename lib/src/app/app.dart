import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../l10n/generated/app_localizations.dart';
import '../pages/home_page.dart';
import 'settings_controller.dart';
import 'theme/app_themes.dart';
import 'theme/wallpaper.dart';

/// Root widget: wires the persisted settings (theme, mode, language,
/// wallpaper) into a [MaterialApp] and renders the wallpaper behind the
/// navigator.
///
/// The app is rebuilt whenever [settings] changes, so theme/locale/wallpaper
/// switches apply instantly and persist across launches.
class DeOptiApp extends StatefulWidget {
  const DeOptiApp({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<DeOptiApp> createState() => _DeOptiAppState();
}

class _DeOptiAppState extends State<DeOptiApp> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) {
        final settings = widget.settings;
        final platformBrightness = MediaQuery.platformBrightnessOf(context);
        final brightness = settings.brightnessOf(platformBrightness);
        final wallpaperActive = settings.wallpaper.isActive;

        return MaterialApp(
          onGenerateTitle: (context) => AppLocalizations.of(context).appName,
          debugShowCheckedModeBanner: false,
          locale: settings.languageCode == null
              ? null
              : Locale(settings.languageCode!),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: buildTheme(
            settings.themeId,
            brightness: brightness,
            translucent: wallpaperActive,
          ),
          darkTheme: buildTheme(
            settings.themeId,
            brightness: Brightness.dark,
            translucent: wallpaperActive,
          ),
          themeMode: switch (settings.themeMode) {
            AppThemeMode.system => ThemeMode.system,
            AppThemeMode.light => ThemeMode.light,
            AppThemeMode.dark => ThemeMode.dark,
          },
          home: const HomePage(),
          builder: (context, child) {
            // Expose settings to the whole tree, resolve strings and paint
            // the wallpaper behind the navigator.
            return _SettingsScope(
              settings: settings,
              child: WallpaperBackground(
                spec: settings.wallpaper,
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
        );
      },
    );
  }
}

/// Injects the [AppSettings] controller into the widget tree; widgets that
/// depend on it rebuild when settings change.
class _SettingsScope extends InheritedNotifier<AppSettings> {
  const _SettingsScope({
    required AppSettings settings,
    required super.child,
  }) : super(notifier: settings);

  static AppSettings of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_SettingsScope>();
    assert(scope != null, 'No AppSettings found above this context');
    return scope!.notifier!;
  }
}

/// Convenience accessor used by pages.
AppSettings appSettingsOf(BuildContext context) => _SettingsScope.of(context);

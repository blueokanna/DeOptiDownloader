/// Material 3 design system for DeOptiDownloader.
///
/// One place owns every visual decision: the theme registry (seed color ×
/// Material 3 "color style" × brightness), the typography (bundled Noto Sans
/// SC), the shape scale and the component themes derived from them. Pages
/// only reference semantic tokens from `Theme.of(context)` — they never
/// hard-code radii, durations or fonts.
///
/// The registry exposes a handful of curated themes, including an AMOLED
/// variant whose surfaces are pure black for OLED screens. Every palette is
/// produced by `ColorScheme.fromSeed` with a `DynamicSchemeVariant` (the
/// Material 3 color style), so contrast and tonal relationships stay
/// algorithmically correct while the seed and style give each theme its
/// character.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Motion durations for the whole app (Material motion tokens).
abstract final class Motion {
  static const Duration shortest = Duration(milliseconds: 100);
  static const Duration short = Duration(milliseconds: 200);
  static const Duration medium = Duration(milliseconds: 300);
  static const Duration long = Duration(milliseconds: 500);

  /// Standard easing (Material 3 "emphasized" feel).
  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeInOutCubic;
}

/// Shape scale (Material 3 shape tokens: extra-small → extra-large).
abstract final class Shape {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 28;

  static RoundedRectangleBorder radius(double r) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));
}

/// How the effective brightness is resolved.
enum AppThemeMode {
  system,
  light,
  dark;

  bool get isDark => this == AppThemeMode.dark;

  /// Resolves the brightness for [platformBrightness] under this mode.
  Brightness resolve(Brightness platformBrightness) {
    switch (this) {
      case AppThemeMode.system:
        return platformBrightness;
      case AppThemeMode.light:
        return Brightness.light;
      case AppThemeMode.dark:
        return Brightness.dark;
    }
  }
}

/// A curated Material 3 theme: seed color × color style × base brightness.
///
/// The `variant` is the Material 3 "color style" (`DynamicSchemeVariant`):
/// tonal spot, expressive, fidelity, vibrant, monochrome, … Each produces a
/// different but always accessible palette from the same seed.
enum ThemeId {
  indigoLight(
    id: 'indigo_light',
    seed: Color(0xFF3D5AFE),
    variant: DynamicSchemeVariant.tonalSpot,
    brightness: Brightness.light,
  ),
  indigoDark(
    id: 'indigo_dark',
    seed: Color(0xFF3D5AFE),
    variant: DynamicSchemeVariant.tonalSpot,
    brightness: Brightness.dark,
  ),
  amoledDark(
    id: 'amoled_dark',
    seed: Color(0xFF9FA8FF),
    variant: DynamicSchemeVariant.tonalSpot,
    brightness: Brightness.dark,
    amoled: true,
  ),
  violet(
    id: 'violet',
    seed: Color(0xFF7C4DFF),
    variant: DynamicSchemeVariant.expressive,
    brightness: Brightness.light,
  ),
  midnight(
    id: 'midnight',
    seed: Color(0xFF3949AB),
    variant: DynamicSchemeVariant.fidelity,
    brightness: Brightness.dark,
  ),
  sunset(
    id: 'sunset',
    seed: Color(0xFFFF6E40),
    variant: DynamicSchemeVariant.vibrant,
    brightness: Brightness.dark,
  ),
  monochrome(
    id: 'monochrome',
    seed: Color(0xFF9E9E9E),
    variant: DynamicSchemeVariant.monochrome,
    brightness: Brightness.light,
  );

  const ThemeId({
    required this.id,
    required this.seed,
    required this.variant,
    required this.brightness,
    this.amoled = false,
  });

  final String id;
  final Color seed;
  final DynamicSchemeVariant variant;
  final Brightness brightness;

  /// Pure-black surfaces for OLED screens (only meaningful for dark themes).
  final bool amoled;

  static ThemeId? fromId(String? id) {
    if (id == null) {
      return null;
    }
    for (final t in ThemeId.values) {
      if (t.id == id) {
        return t;
      }
    }
    return null;
  }

  /// All themes, grouped by effective brightness for the settings page.
  static List<ThemeId> ofBrightness(Brightness brightness) => values
      .where((t) => t.brightness == brightness || t.amoled)
      .toList(growable: false);
}

/// A convenience accessor matching the old `theme.dart` API.
const Color kSeedColor = Color(0xFF3D5AFE);

/// Builds the full [ThemeData] for [theme] at [brightness].
///
/// When [translucent] is true (a wallpaper is active) the surface tones are
/// given a small alpha so the background image glows through the UI; the
/// readable on-* colors are untouched, so contrast is preserved.
ThemeData buildTheme(
  ThemeId theme, {
  required Brightness brightness,
  bool translucent = false,
}) {
  var scheme = ColorScheme.fromSeed(
    seedColor: theme.seed,
    brightness: brightness,
    dynamicSchemeVariant: theme.variant,
  );

  if (theme.amoled) {
    // True black surfaces for OLED: keep the seeded tonal palette for
    // containers/primary but pin the base surfaces to pure black.
    scheme = scheme.copyWith(
      surface: Colors.black,
      surfaceDim: Colors.black,
      surfaceBright: const Color(0xFF141414),
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: Colors.black,
      surfaceContainer: const Color(0xFF0E0E0E),
      surfaceContainerHigh: const Color(0xFF1A1A1A),
      surfaceContainerHighest: const Color(0xFF242424),
      onSurface: Colors.white,
      onSurfaceVariant: const Color(0xFFC7C5D0),
      outline: const Color(0xFF8B8A94),
      outlineVariant: const Color(0xFF3B3B40),
    );
  }

  if (translucent) {
    final surface = scheme.surface.withValues(alpha: 0.84);
    scheme = scheme.copyWith(
      surface: surface,
      surfaceContainerLowest: scheme.surfaceContainerLowest.withValues(alpha: 0.84),
      surfaceContainerLow: scheme.surfaceContainerLow.withValues(alpha: 0.84),
      surfaceContainer: scheme.surfaceContainer.withValues(alpha: 0.80),
      surfaceContainerHigh: scheme.surfaceContainerHigh.withValues(alpha: 0.80),
      surfaceContainerHighest: scheme.surfaceContainerHighest.withValues(alpha: 0.76),
    );
  }

  // Bundled Noto Sans SC — never touches the network.
  final baseText = ThemeData(brightness: brightness).textTheme;
  final textTheme = GoogleFonts.notoSansScTextTheme(baseText).apply(
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    textTheme: textTheme,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    splashFactory: InkSparkle.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );

  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 1,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      margin: EdgeInsets.zero,
      shape: Shape.radius(Shape.lg),
      clipBehavior: Clip.antiAlias,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: Shape.radius(Shape.md),
        textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: Shape.radius(Shape.md),
        side: BorderSide(color: scheme.outlineVariant),
        textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: Shape.radius(Shape.sm),
        textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(shape: Shape.radius(Shape.sm)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Shape.md),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Shape.md),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Shape.md),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    dialogTheme: DialogThemeData(
      shape: Shape.radius(Shape.xl),
      backgroundColor: scheme.surfaceContainerLow,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: Shape.radius(Shape.md),
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: textTheme.bodyMedium?.copyWith(
        color: scheme.onInverseSurface,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.secondaryContainer,
      height: 72,
      elevation: 0,
      labelTextStyle: WidgetStatePropertyAll(
        textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w500),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: Shape.radius(Shape.sm),
      side: BorderSide(color: scheme.outlineVariant),
      backgroundColor: scheme.surfaceContainerLow,
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHighest,
      circularTrackColor: scheme.surfaceContainerHighest,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(Shape.xs),
      ),
      textStyle: textTheme.bodySmall?.copyWith(color: scheme.onInverseSurface),
    ),
    listTileTheme: ListTileThemeData(
      shape: Shape.radius(Shape.md),
      iconColor: scheme.onSurfaceVariant,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.onPrimary
            : scheme.outline,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.primary
            : scheme.surfaceContainerHighest,
      ),
    ),
  );
}

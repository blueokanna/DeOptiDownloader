/// Material 3 design system for DeOptiDownloader.
///
/// One place owns every visual decision: ColorSpec (seed color) x ColorStyle
/// (Material dynamic scheme variant), the typography (bundled Noto Sans
/// SC), the shape scale and the component themes derived from them. Pages
/// only reference semantic tokens from `Theme.of(context)` — they never
/// hard-code radii, durations or fonts.
///
/// Color specification, style, brightness and AMOLED surfaces are independent.
/// Every palette is produced by `ColorScheme.fromSeed` with a
/// `DynamicSchemeVariant`, so contrast and tonal relationships stay
/// algorithmically correct for every supported combination.
library;

import 'package:flutter/material.dart';

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

/// Seed-color specifications offered by the app. Brightness and palette
/// generation style are deliberately independent from this choice.
enum ColorSpec {
  indigo(id: 'indigo', seed: Color(0xFF3D5AFE)),
  cyan(id: 'cyan', seed: Color(0xFF006C7A)),
  emerald(id: 'emerald', seed: Color(0xFF006B57)),
  violet(id: 'violet', seed: Color(0xFF7C4DFF)),
  sunset(id: 'sunset', seed: Color(0xFFB33C16)),
  neutral(id: 'neutral', seed: Color(0xFF60646C));

  const ColorSpec({required this.id, required this.seed});

  final String id;
  final Color seed;

  static ColorSpec? fromId(String? id) {
    if (id == null) {
      return null;
    }
    for (final spec in ColorSpec.values) {
      if (spec.id == id) {
        return spec;
      }
    }
    return null;
  }
}

/// Material 3 palette generation styles backed by Flutter's real
/// [DynamicSchemeVariant] implementation.
enum ColorStyle {
  tonalSpot(id: 'tonal_spot', variant: DynamicSchemeVariant.tonalSpot),
  expressive(id: 'expressive', variant: DynamicSchemeVariant.expressive),
  fidelity(id: 'fidelity', variant: DynamicSchemeVariant.fidelity),
  vibrant(id: 'vibrant', variant: DynamicSchemeVariant.vibrant),
  neutral(id: 'neutral', variant: DynamicSchemeVariant.neutral),
  monochrome(id: 'monochrome', variant: DynamicSchemeVariant.monochrome);

  const ColorStyle({required this.id, required this.variant});

  final String id;
  final DynamicSchemeVariant variant;

  static ColorStyle? fromId(String? id) {
    if (id == null) {
      return null;
    }
    for (final style in ColorStyle.values) {
      if (style.id == id) {
        return style;
      }
    }
    return null;
  }
}

/// A convenience accessor matching the old `theme.dart` API.
const Color kSeedColor = Color(0xFF3D5AFE);

/// Builds the full [ThemeData] for [colorSpec] and [colorStyle].
///
/// When [translucent] is true (a wallpaper is active) the surface tones are
/// given a small alpha so the background image glows through the UI; the
/// readable on-* colors are untouched, so contrast is preserved.
ThemeData buildTheme(
  ColorSpec colorSpec,
  ColorStyle colorStyle, {
  required Brightness brightness,
  bool amoled = false,
  bool translucent = false,
}) {
  var scheme = ColorScheme.fromSeed(
    seedColor: colorSpec.seed,
    brightness: brightness,
    dynamicSchemeVariant: colorStyle.variant,
  );

  if (amoled && brightness == Brightness.dark) {
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
      surfaceContainerLowest: scheme.surfaceContainerLowest.withValues(
        alpha: 0.84,
      ),
      surfaceContainerLow: scheme.surfaceContainerLow.withValues(alpha: 0.84),
      surfaceContainer: scheme.surfaceContainer.withValues(alpha: 0.80),
      surfaceContainerHigh: scheme.surfaceContainerHigh.withValues(alpha: 0.80),
      surfaceContainerHighest: scheme.surfaceContainerHighest.withValues(
        alpha: 0.76,
      ),
    );
  }

  // Bundled Noto Sans SC — never touches the network.
  final baseText = ThemeData(
    brightness: brightness,
    fontFamily: 'NotoSansSC',
  ).textTheme;
  final textTheme = baseText.apply(
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: 'NotoSansSC',
    textTheme: textTheme,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    splashFactory: InkSparkle.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(
          backgroundColor: Colors.transparent,
        ),
        TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(
          backgroundColor: Colors.transparent,
        ),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(
          backgroundColor: Colors.transparent,
        ),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(
          backgroundColor: Colors.transparent,
        ),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(
          backgroundColor: Colors.transparent,
        ),
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

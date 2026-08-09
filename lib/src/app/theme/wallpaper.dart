/// Wallpaper support: a selectable background rendered behind the whole app.
///
/// Three kinds are supported:
/// - `none`    — plain theme surfaces (no image, no blur control needed);
/// - `builtin` — a bundled gradient wallpaper (`assets/images/wallpapers/…`);
/// - `custom`  — an image the user picked from their gallery, with a
///   draggable blur (sigma) that softens the image behind the UI.
///
/// The background is rendered once in `DeOptiApp`'s builder as the bottom
/// layer of a `Stack`; every `Scaffold` above it uses semi-transparent
/// surfaces (see `buildTheme(translucent:)`) so the wallpaper glows through.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// The built-in wallpaper asset ids (files live in `assets/images/wallpapers/`).
const List<String> kBuiltinWallpapers = [
  'aurora',
  'sunset',
  'ocean',
  'forest',
  'nebula',
];

/// Where the background image comes from.
enum WallpaperKind {
  none,
  builtin,
  custom,
}

/// Immutable description of the current wallpaper.
@immutable
class WallpaperSpec {
  const WallpaperSpec.none() : kind = WallpaperKind.none, assetId = null, imagePath = null, blur = 0;

  const WallpaperSpec.builtin(this.assetId)
      : kind = WallpaperKind.builtin,
        imagePath = null,
        blur = 0;

  const WallpaperSpec.custom(this.imagePath, {this.blur = 0})
      : kind = WallpaperKind.custom,
        assetId = null;

  final WallpaperKind kind;
  final String? assetId;
  final String? imagePath;

  /// Gaussian blur sigma (0 = sharp, up to ~24 = heavily frosted).
  final double blur;

  bool get isActive => kind != WallpaperKind.none;

  double get effectiveBlur => isActive ? blur.clamp(0, 24) : 0;

  WallpaperSpec copyWith({double? blur}) => switch (kind) {
        WallpaperKind.none => const WallpaperSpec.none(),
        WallpaperKind.builtin => WallpaperSpec.builtin(assetId!),
        WallpaperKind.custom => WallpaperSpec.custom(
            imagePath!,
            blur: blur ?? this.blur,
          ),
      };
}

/// Paints the wallpaper image (with optional gaussian blur) filling the
/// available area, then lays [child] on top. When `kind == none` this is a
/// pass-through so there is no rendering cost at all.
class WallpaperBackground extends StatelessWidget {
  const WallpaperBackground({
    super.key,
    required this.spec,
    required this.child,
  });

  final WallpaperSpec spec;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final image = _resolveImage();
    if (image == null) {
      return child;
    }
    Widget layer = image;
    if (spec.effectiveBlur > 0.01) {
      layer = ImageFiltered(
        imageFilter: ImageFilter.blur(
          sigmaX: spec.effectiveBlur,
          sigmaY: spec.effectiveBlur,
        ),
        child: layer,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: Theme.of(context).colorScheme.surface,
          child: layer,
        ),
        child,
      ],
    );
  }

  Widget? _resolveImage() {
    switch (spec.kind) {
      case WallpaperKind.none:
        return null;
      case WallpaperKind.builtin:
        return Image.asset(
          'assets/images/wallpapers/${spec.assetId}.png',
          fit: BoxFit.cover,
          gaplessPlayback: true,
        );
      case WallpaperKind.custom:
        final path = spec.imagePath;
        if (path == null || path.isEmpty) {
          return null;
        }
        if (path.startsWith('data:')) {
          // Web persistence: base64 data URI.
          final header = 'base64,';
          final idx = path.indexOf(header);
          if (idx < 0) {
            return null;
          }
          try {
            final bytes = base64Decode(path.substring(idx + header.length));
            return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
          } catch (_) {
            return null;
          }
        }
        return Image.file(File(path), fit: BoxFit.cover, gaplessPlayback: true);
    }
  }
}

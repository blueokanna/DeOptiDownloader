import 'package:flutter/material.dart';

/// Responsive breakpoints shared by every screen (Material guidance).
///
/// The app is deployed to phones, tablets, desktops, Web and HarmonyOS
/// windows of very different sizes, so no screen hard-codes a layout: each
/// one adapts through [Responsive.of] / [ResponsiveBox] instead.
abstract final class Responsive {
  /// Compact (phone) — single column, bottom bars.
  static const double compact = 600;

  /// Medium (foldable / small tablet) — wider margins, two-pane hints.
  static const double medium = 840;

  /// Expanded (desktop / Web) — multi-pane, navigation rail.
  static const double expanded = 1200;

  /// Maximum content width so text lines stay readable on ultra-wide screens.
  static const double maxContentWidth = 900;

  /// Resolves the breakpoint class for [size].
  static Breakpoint of(Size size) {
    final w = size.width;
    if (w < compact) {
      return Breakpoint.compact;
    }
    if (w < medium) {
      return Breakpoint.medium;
    }
    if (w < expanded) {
      return Breakpoint.expanded;
    }
    return Breakpoint.wide;
  }

  /// Convenience: `Responsive.of(context).isCompact` style usage.
  static Breakpoint ofContext(BuildContext context) =>
      of(MediaQuery.sizeOf(context));

  /// Horizontal page padding for each breakpoint.
  static EdgeInsets paddingOf(BuildContext context) {
    switch (ofContext(context)) {
      case Breakpoint.compact:
        return const EdgeInsets.all(16);
      case Breakpoint.medium:
        return const EdgeInsets.symmetric(horizontal: 24, vertical: 20);
      case Breakpoint.expanded:
      case Breakpoint.wide:
        return const EdgeInsets.symmetric(horizontal: 32, vertical: 24);
    }
  }
}

/// Screen-size class used by `switch` statements in page layouts.
enum Breakpoint {
  compact,
  medium,
  expanded,
  wide;

  bool get isCompact => this == Breakpoint.compact;
  bool get isWide => this == Breakpoint.expanded || this == Breakpoint.wide;
}

/// Centers [child] with a max width while keeping it full-height, so tablets
/// and desktops get comfortable column widths without stretching widgets.
class ResponsiveBox extends StatelessWidget {
  const ResponsiveBox({
    super.key,
    required this.child,
    this.maxWidth = Responsive.maxContentWidth,
    this.padding,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding ?? Responsive.paddingOf(context),
          child: child,
        ),
      ),
    );
  }
}

/// Grid spacing helper for two-pane layouts on wide screens.
abstract final class GridSpacing {
  static double gutter(BuildContext context) =>
      Responsive.ofContext(context).isWide ? 24 : 16;
}

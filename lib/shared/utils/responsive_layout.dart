import 'package:flutter/material.dart';

/// Standard Material 3 / Adaptive Responsive Breakpoints
class ResponsiveBreakpoints {
  /// Mobile phones / compact viewports (< 600dp)
  static const double compactMax = 600.0;

  /// Foldables / small tablets in portrait (600dp - 840dp)
  static const double mediumMax = 840.0;

  /// Large tablets (10" to 14"), landscape tablets, desktops (>= 840dp)
  static const double expandedMin = 840.0;

  /// Maximum recommended width for single-column form views
  static const double maxFormWidth = 520.0;

  /// Maximum recommended width for wide content containers
  static const double maxContentWidth = 1200.0;
}

/// Convenience extension on [BuildContext] for responsive layout decisions.
extension ResponsiveContext on BuildContext {
  Size get screenSize => MediaQuery.sizeOf(this);
  double get screenWidth => screenSize.width;
  double get screenHeight => screenSize.height;

  Orientation get orientation => MediaQuery.orientationOf(this);
  bool get isLandscape => orientation == Orientation.landscape;
  bool get isPortrait => orientation == Orientation.portrait;

  /// Width < 600dp
  bool get isCompact => screenWidth < ResponsiveBreakpoints.compactMax;

  /// Width 600dp .. 840dp
  bool get isMedium =>
      screenWidth >= ResponsiveBreakpoints.compactMax &&
      screenWidth < ResponsiveBreakpoints.mediumMax;

  /// Width >= 840dp
  bool get isExpanded => screenWidth >= ResponsiveBreakpoints.expandedMin;

  /// Width >= 600dp (Tablets, foldables, desktops) or Landscape mode with width >= 560dp
  bool get isTabletOrDesktop => screenWidth >= ResponsiveBreakpoints.compactMax || (isLandscape && screenWidth >= 560);

  /// Helper to pick responsive values dynamically based on breakpoint.
  T responsiveValue<T>({
    required T compact,
    T? medium,
    T? expanded,
  }) {
    if (isExpanded && expanded != null) return expanded;
    if (isMedium && medium != null) return medium;
    return compact;
  }
}

/// A layout container that centers content on wide screens with a maximum width constraint.
class ResponsiveContainer extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;
  final AlignmentGeometry alignment;

  const ResponsiveContainer({
    super.key,
    required this.child,
    this.maxWidth = 640.0,
    this.padding,
    this.alignment = Alignment.topCenter,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    );

    if (padding != null) {
      content = Padding(
        padding: padding!,
        child: content,
      );
    }

    return Align(
      alignment: alignment,
      child: content,
    );
  }
}

/// Automatically renders two panes side-by-side on wide/landscape screens
/// and vertically stacked on compact mobile screens.
class ResponsiveTwoPane extends StatelessWidget {
  final Widget pane1;
  final Widget pane2;
  final int pane1Flex;
  final int pane2Flex;
  final double breakpoint;
  final double spacing;
  final EdgeInsetsGeometry padding;
  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisAlignment mainAxisAlignment;

  const ResponsiveTwoPane({
    super.key,
    required this.pane1,
    required this.pane2,
    this.pane1Flex = 1,
    this.pane2Flex = 1,
    this.breakpoint = ResponsiveBreakpoints.expandedMin,
    this.spacing = 24.0,
    this.padding = const EdgeInsets.all(24.0),
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.mainAxisAlignment = MainAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= breakpoint;

        if (isWide) {
          return Padding(
            padding: padding,
            child: Row(
              crossAxisAlignment: crossAxisAlignment,
              mainAxisAlignment: mainAxisAlignment,
              children: [
                Expanded(
                  flex: pane1Flex,
                  child: pane1,
                ),
                SizedBox(width: spacing),
                Expanded(
                  flex: pane2Flex,
                  child: pane2,
                ),
              ],
            ),
          );
        } else {
          return Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: mainAxisAlignment,
              children: [
                pane1,
                SizedBox(height: spacing),
                pane2,
              ],
            ),
          );
        }
      },
    );
  }
}

import 'dart:math' as math;

/// Logical dimensions used to keep the guide readable across available areas.
class GuideLayoutProfile {
  /// The guide renders a fixed 2.5-hour span at every width. Holding the span
  /// constant instead of widening it with the viewport is what keeps a
  /// programme cell wide enough for its title to be readable.
  static const Duration guideWindow = Duration(minutes: 150);

  final double rowHeight;
  final double channelColumnWidth;
  final double pixelsPerMinute;
  final double timeHeaderHeight;
  final int targetSlots;

  const GuideLayoutProfile({
    required this.rowHeight,
    required this.channelColumnWidth,
    required this.pixelsPerMinute,
    required this.timeHeaderHeight,
    required this.targetSlots,
  });

  /// Derives guide dimensions from logical layout constraints and text scale.
  factory GuideLayoutProfile.fromAvailableArea({
    required double availableWidth,
    required double availableHeight,
    double textScaleFactor = 1.0,
  }) {
    final width = math.max(1.0, availableWidth);
    final scale = math.max(1.0, textScaleFactor);
    final densityHeight = math.max(1.0, availableHeight) / scale;
    final heightProgress = ((densityHeight - 320) / 480).clamp(0.0, 1.0);
    final channelColumnWidth = (width * 0.2).clamp(120.0, 240.0);
    final guideWidth = math.max(1.0, width - channelColumnWidth);

    return GuideLayoutProfile(
      rowHeight: 50 + (6 * heightProgress),
      channelColumnWidth: channelColumnWidth,
      pixelsPerMinute: guideWidth / guideWindow.inMinutes,
      timeHeaderHeight: 22 + (2 * heightProgress),
      targetSlots: guideWindow.inMinutes ~/ 30,
    );
  }
}

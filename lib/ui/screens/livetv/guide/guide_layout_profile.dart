import 'dart:math' as math;

/// Logical dimensions used to keep the guide readable across available areas.
class GuideLayoutProfile {
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
    final targetSlots = width < 720
        ? 8
        : width < 1100
        ? 12
        : 16;
    final guideWidth = math.max(1.0, width - channelColumnWidth);

    return GuideLayoutProfile(
      rowHeight: 50 + (6 * heightProgress),
      channelColumnWidth: channelColumnWidth,
      pixelsPerMinute: guideWidth / (targetSlots * 30),
      timeHeaderHeight: 22 + (2 * heightProgress),
      targetSlots: targetSlots,
    );
  }

  /// Derives the fetched window span from the same profile the grid renders.
  int guideHoursForWidth(double availableWidth) {
    final guideWidth = availableWidth - channelColumnWidth;
    if (guideWidth <= 0) return 3;
    final hours = (guideWidth / (pixelsPerMinute * 60)).floor();
    return hours.clamp(3, 12);
  }
}

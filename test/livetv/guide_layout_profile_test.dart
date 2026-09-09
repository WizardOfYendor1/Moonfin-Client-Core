import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/screens/livetv/guide/guide_layout_profile.dart';

void main() {
  test('keeps row and header density within the logical ranges', () {
    for (final height in [240.0, 360.0, 540.0, 900.0, 1400.0]) {
      final profile = GuideLayoutProfile.fromAvailableArea(
        availableWidth: 960,
        availableHeight: height,
      );

      expect(profile.rowHeight, inInclusiveRange(50, 56));
      expect(profile.timeHeaderHeight, inInclusiveRange(22, 24));
    }
  });

  test('derives positive time density and bounded fetch windows', () {
    for (final width in [120.0, 240.0, 480.0, 720.0, 960.0, 1920.0, 3840.0]) {
      final profile = GuideLayoutProfile.fromAvailableArea(
        availableWidth: width,
        availableHeight: 540,
        textScaleFactor: 1.5,
      );

      expect(profile.pixelsPerMinute, greaterThan(0));
      expect(
        profile.guideWindowForWidth(width).inMinutes,
        inInclusiveRange(
          GuideLayoutProfile.minGuideWindow.inMinutes,
          GuideLayoutProfile.maxGuideWindow.inMinutes,
        ),
      );
    }
  });

  test('shows a 2.5-hour window of programming at every width', () {
    expect(GuideLayoutProfile.guideWindow, const Duration(minutes: 150));

    for (final width in [120.0, 240.0, 480.0, 720.0, 960.0, 1920.0, 3840.0]) {
      final profile = GuideLayoutProfile.fromAvailableArea(
        availableWidth: width,
        availableHeight: 540,
      );

      // Five half-hour ticks, and a rendered window that exactly fills the
      // grid: pixelsPerMinute * 150 is the guide area's width.
      expect(profile.targetSlots, 5);
      expect(
        profile.guideWindowForWidth(width),
        const Duration(minutes: 150),
        reason: 'width $width',
      );
      expect(
        profile.pixelsPerMinute * 150,
        // The profile floors the guide area at one pixel, which only bites at
        // widths the channel column alone consumes.
        closeTo(math.max(1.0, width - profile.channelColumnWidth), 0.0001),
        reason: 'width $width',
      );
    }
  });

  test('gives a 30-minute cell a readable width on a 1080p television', () {
    // 1920 physical at density 2 is 960 logical; the channel column is 192 of
    // it, leaving 768 for 150 minutes.
    final profile = GuideLayoutProfile.fromAvailableArea(
      availableWidth: 960,
      availableHeight: 540,
    );

    expect(profile.channelColumnWidth, 192);
    expect(profile.pixelsPerMinute, closeTo(5.12, 0.0001));
    expect(30 * profile.pixelsPerMinute, closeTo(153.6, 0.0001));
  });
}

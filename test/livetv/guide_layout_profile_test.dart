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
      expect(profile.guideHoursForWidth(width), inInclusiveRange(3, 12));
    }
  });
}

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/util/tv_ui_scale.dart';

void main() {
  group('the TV design canvas', () {
    test('is the same whatever density the panel reports', () {
      // tvOS hands Flutter 1920 points across. A 1080p Android TV at density
      // two hands it 960. Both have to lay out on the same canvas, or the ten
      // foot constants land at different sizes on each.
      final tvos = tvUiLogicalSize(const Size(1920, 1080));
      final androidTv = tvUiLogicalSize(const Size(960, 540));

      expect(tvos.width, closeTo(kTvDesignWidth, 0.01));
      expect(androidTv.width, closeTo(kTvDesignWidth, 0.01));
      expect(tvos.height, closeTo(androidTv.height, 0.01));
      expect(tvos.height, closeTo(620.7, 0.5));
    });

    test('drives a 1080p panel at the scale the layouts were drawn for', () {
      expect(tvUiScaleFor(1920), closeTo(kTvTargetScale, 0.001));
      expect(tvUiScaleFor(960), closeTo(kTvTargetScale / 2, 0.001));
    });

    test('leaves the effective density the same on both', () {
      // What the panel ends up painting at is the density it reported times
      // the magnification. Both land on 1.74, which is 1920 real pixels.
      const tvosReported = 1.0;
      const androidTvReported = 2.0;
      expect(
        tvosReported * tvUiScaleFor(1920),
        closeTo(androidTvReported * tvUiScaleFor(960), 0.001),
      );
    });

    test('is a no-op on a panel already at the design width', () {
      expect(tvUiScaleIsNegligible(kTvDesignWidth), isTrue);
      expect(tvUiScaleIsNegligible(1920), isFalse);
      expect(tvUiScaleIsNegligible(960), isFalse);
    });

    test("doesn't divide by a width the platform hasn't reported yet", () {
      expect(tvUiScaleFor(0), 1.0);
      expect(tvUiLogicalSize(Size.zero), Size.zero);
    });

    test('a 4K panel lands on the same canvas as a 1080p one', () {
      expect(
        tvUiLogicalSize(const Size(3840, 2160)).width,
        closeTo(tvUiLogicalSize(const Size(1920, 1080)).width, 0.01),
      );
    });
  });
}

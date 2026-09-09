import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/widgets/live_tv/channel_carousel_controller.dart';

void main() {
  test('a lineup that fits the viewport advances one channel per repeat', () {
    // Paging by the visible count would give (i + 3) % 3 == i — motionless.
    expect(pageStep(channelCount: 3, visibleCards: 5), 1);
    expect(pageStep(channelCount: 5, visibleCards: 5), 1);
  });

  test('a larger lineup pages by the visible count', () {
    expect(pageStep(channelCount: 48, visibleCards: 5), 5);
  });

  test('a single channel does not move', () {
    expect(pageStep(channelCount: 1, visibleCards: 5), 0);
  });

  test('index mapping wraps in both directions', () {
    expect(channelIndexFor(0, 3), 0);
    expect(channelIndexFor(4, 3), 1);
    expect(channelIndexFor(-1, 3), 2);
  });

  test('recentring preserves the selected channel', () {
    const count = 48;
    const seed = count * 500;
    final raw = seed + 3;
    expect(channelIndexFor(recentre(raw, count, seed), count),
        channelIndexFor(raw, count));
  });

  test('recentring preserves selection when drifted forward', () {
    const count = 48;
    const seed = count * 500;
    final raw = seed + count * 300 + 17;
    expect(needsRecentre(raw, count, seed), isTrue);
    expect(channelIndexFor(recentre(raw, count, seed), count),
        channelIndexFor(raw, count));
  });

  test('recentring preserves selection when drifted backward', () {
    const count = 48;
    const seed = count * 500;
    final raw = seed - count * 300 - 17;
    expect(needsRecentre(raw, count, seed), isTrue);
    expect(channelIndexFor(recentre(raw, count, seed), count),
        channelIndexFor(raw, count));
  });

  test('recentre lands the raw index back near the seed', () {
    const count = 48;
    const seed = count * 500;
    final raw = seed + count * 300 + 17;
    final recentred = recentre(raw, count, seed);
    expect(needsRecentre(recentred, count, seed), isFalse);
  });

  test('a small drift does not trigger recentring', () {
    const count = 48;
    const seed = count * 500;
    expect(needsRecentre(seed + 3, count, seed), isFalse);
  });
}

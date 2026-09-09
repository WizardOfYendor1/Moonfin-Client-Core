import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/theme/app_theme.dart';
import 'package:moonfin/ui/widgets/live_tv/channel_carousel.dart';
import 'package:moonfin_design/moonfin_design.dart';

/// 900 dp of strip at a 180 dp card pitch is exactly five visible cards, which
/// is what makes `pageStep` observable: 20 channels page by five, three page
/// by one.
const double _stripWidth = 900;

List<ChannelCarouselEntry> _lineup(int count) => List.generate(
      count,
      (i) => ChannelCarouselEntry(
        channelId: 'ch$i',
        channelName: 'Channel $i',
        channelNumber: '${i + 1}',
        programTitle: 'Program $i',
        timeLabel: '8:00 PM - 9:00 PM',
        isLive: true,
        progress: 0.5,
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => ThemeRegistry.setActiveById(ThemeRegistry.moonfinId));

  tearDown(() => HardwareKeyboard.instance.clearState());

  /// Pumps the strip and returns the list of centred channel indices, in the
  /// order the widget reported them.
  Future<List<int>> pumpCarousel(WidgetTester tester, int channelCount) async {
    await tester.binding.setSurfaceSize(const Size(1000, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final centred = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildTheme(ThemeRegistry.active),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: _stripWidth,
              child: ChannelCarousel(
                channels: _lineup(channelCount),
                onChannelCentered: centred.add,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return centred;
  }

  testWidgets('a held key whose repeats keep arriving pages past 1000 ms',
      (tester) async {
    final centred = await pumpCarousel(tester, 20);

    // Key-down pages one card, then the 350 ms timer starts the hold cadence.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    // Physical repeats every 100 ms out to 1200 ms, refreshing the watchdog.
    for (var elapsed = 100; elapsed <= 900; elapsed += 100) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    }
    // Key-down at 0 ms and the first hold page at 350 ms.
    final pagesBy900ms = centred.length;
    expect(pagesBy900ms, 2);

    for (var elapsed = 1000; elapsed <= 1200; elapsed += 100) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    }

    // The second hold page falls at 350 + 650 = 1000 ms. A watchdog measured
    // from key-down would have cancelled the hold at 900 ms and lost it.
    expect(centred.length, greaterThan(pagesBy900ms));

    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
  });

  testWidgets('paging halts within ~900 ms of the last repeat when no key-up '
      'arrives', (tester) async {
    final centred = await pumpCarousel(tester, 20);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    // Repeats stop at 400 ms; no key-up ever arrives.
    for (var elapsed = 100; elapsed <= 400; elapsed += 100) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    }

    // 400 ms + the 900 ms watchdog. The hold page at 1000 ms still lands; the
    // one that would follow at 1650 ms must not.
    await tester.pump(const Duration(milliseconds: 900));
    final pagesAtWatchdog = centred.length;
    expect(pagesAtWatchdog, 3);

    await tester.pump(const Duration(seconds: 2));
    expect(centred.length, pagesAtWatchdog);
  });

  testWidgets('timer-generated pages do not keep the watchdog alive',
      (tester) async {
    final centred = await pumpCarousel(tester, 20);

    // Key-down only: the hold's own timers are the sole source of paging.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(centred.length, 2, reason: 'key-down page plus the 350 ms page');

    // The 350 ms page cannot postpone the watchdog, so it fires at 900 ms and
    // the 1000 ms page never happens.
    await tester.pump(const Duration(seconds: 2));
    expect(centred.length, 2);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
  });

  testWidgets('a 3-channel lineup with 5 visible cards advances one channel '
      'per repeat', (tester) async {
    final centred = await pumpCarousel(tester, 3);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    for (var elapsed = 100; elapsed <= 1200; elapsed += 100) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    }

    // Paging by the visible count would give (i + 5) % 3, which is not the
    // next channel; paging by three would be motionless.
    expect(centred, [1, 2, 0]);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
  });
}

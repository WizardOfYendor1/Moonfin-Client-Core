import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/viewmodels/live_tv_guide_view_model.dart';
import 'package:moonfin/ui/theme/app_theme.dart';
import 'package:moonfin/ui/widgets/live_tv/channel_carousel.dart';
import 'package:moonfin/ui/widgets/live_tv/channel_carousel_card.dart';
import 'package:moonfin/ui/widgets/live_tv/channel_carousel_overlay.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';

class _CarouselClient extends Mock implements MediaServerClient {}

class _CarouselGuide extends LiveTvGuideViewModel {
  final List<GuideChannel> lineup;
  final List<List<String>> requests = [];
  bool disposed = false;
  int schedules = 0;
  bool get listening => hasListeners;
  String titleSuffix = '';

  void changeProgram() {
    titleSuffix = ' updated';
    notifyListeners();
  }

  _CarouselGuide(super.client, this.lineup);

  @override
  List<GuideChannel> get filteredChannels => lineup;

  @override
  GuideChannel? channelForId(String channelId) =>
      lineup.where((channel) => channel.id == channelId).firstOrNull;

  @override
  List<GuideProgram> unfilteredProgramsForChannel(String channelId) {
    final now = DateTime.now();
    return [GuideProgram(
      id: '$channelId-program', channelId: channelId,
      name: 'Show $channelId$titleSuffix',
      startDate: now.subtract(const Duration(minutes: 20)),
      endDate: now.add(const Duration(minutes: 40)),
      overview: 'Overview $channelId',
      rawData: const {'ParentIndexNumber': 6, 'IndexNumber': 19},
    )];
  }

  @override
  Future<void> load({int? windowHours, List<String>? initialChannelIds,
      DateTime? windowStart, bool livePosition = true}) async {
    requests.add(initialChannelIds!);
    notifyListeners();
  }

  @override
  Future<void> ensureProgramsForChannels(List<String> channelIds) async {
    requests.add(channelIds);
  }

  @override
  void scheduleBoundaryRefresh() { schedules++; }

  @override
  Future<void> refreshAtQuarterHour() async {}

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

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

  Future<_CarouselGuide> pumpOverlay(WidgetTester tester,
      {VoidCallback? onDismiss, VoidCallback? onShowControls,
      Duration inactivity = const Duration(seconds: 5)}) async {
    await tester.binding.setSurfaceSize(const Size(1000, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = _CarouselClient();
    final channels = List.generate(20, (i) => GuideChannel(
      id: 'ch$i', name: 'Channel $i', number: '${i + 1}', rawData: const {},
    ));
    final vm = _CarouselGuide(client, channels);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.buildTheme(ThemeRegistry.active),
      home: Scaffold(body: ChannelCarouselOverlay(
        client: client, channels: channels, currentChannelId: 'ch10',
        onChannelSelected: (_) {}, onDismiss: onDismiss ?? () {},
        onShowControls: onShowControls ?? () {}, inactivityDuration: inactivity,
        viewModelFactory: (_) => vm,
      )),
    ));
    await tester.pump();
    await tester.pump();
    return vm;
  }

  testWidgets('overlay header waits until 300 ms after scrolling ends',
      (tester) async {
    await pumpOverlay(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Show ch10 (S6:E19)'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Show ch11 (S6:E19)'), findsNothing);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 299));
    expect(find.text('Show ch11 (S6:E19)'), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('Show ch11 (S6:E19)'), findsOneWidget);
    expect(find.text('Overview ch11'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('overlay owns and disposes its guide and forwards resume',
      (tester) async {
    final vm = await pumpOverlay(tester);
    expect(vm.listening, isTrue);
    expect(vm.requests.first, contains('ch10'));
    expect(vm.requests.first.length, lessThan(20));
    final before = vm.schedules;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(vm.schedules, greaterThan(before));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(vm.disposed, isTrue);
    expect(vm.listening, isFalse);
  });

  testWidgets('overlay debounces visible loads and follows data notifications',
      (tester) async {
    final vm = await pumpOverlay(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 299));
    expect(vm.requests, hasLength(1));
    await tester.pump(const Duration(milliseconds: 1));
    expect(vm.requests, hasLength(2));
    expect(vm.requests.last, contains('ch12'));
    vm.changeProgram();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Show ch12 updated (S6:E19)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('overlay inactivity resets on key down, repeat and key up',
      (tester) async {
    var dismissals = 0;
    await pumpOverlay(tester, onDismiss: () => dismissals++);
    await tester.pump(const Duration(seconds: 4));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump(const Duration(seconds: 4));
    expect(dismissals, 0);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump(const Duration(seconds: 4));
    expect(dismissals, 0);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump(const Duration(milliseconds: 4999));
    expect(dismissals, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(dismissals, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('DOWN requests controls without taking the restoration callback',
      (tester) async {
    var dismissals = 0;
    var controls = 0;
    await pumpOverlay(tester, onDismiss: () => dismissals++,
        onShowControls: () => controls++);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(controls, 1);
    expect(dismissals, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  /// Pumps the strip and returns the list of centred channel indices, in the
  /// order the widget reported them.
  Future<List<int>> pumpCarousel(WidgetTester tester, int channelCount,
      {int initialIndex = 0, double width = _stripWidth}) async {
    await tester.binding.setSurfaceSize(const Size(1000, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final centred = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildTheme(ThemeRegistry.active),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: ChannelCarousel(
                channels: _lineup(channelCount),
                initialIndex: initialIndex,
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

  testWidgets('scrolling carousel has a finite range and wraps left at zero',
      (tester) async {
    final centered = await pumpCarousel(tester, 20);
    final list = tester.widget<ListView>(find.byType(ListView));
    final delegate = list.childrenDelegate as SliverChildBuilderDelegate;
    expect(delegate.childCount, isNotNull);
    expect(delegate.childCount, greaterThan(1000));
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.maxScrollExtent.isFinite, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(centered, [19]);
    final selected = find.byWidgetPredicate(
        (widget) => widget is ChannelCarouselCard && widget.centered);
    expect(tester.widget<ChannelCarouselCard>(selected).channelName, 'Channel 19');
    expect(tester.getCenter(selected).dx, closeTo(500, 0.01));
  });

  for (final channelCount in [1, 2, 3, 4, 5]) {
    testWidgets('$channelCount fitting channels pin a non-middle initial '
        'selection and wrap to the viewport center', (tester) async {
      await pumpCarousel(tester, channelCount, initialIndex: channelCount - 1);
      Finder selected() => find.byWidgetPredicate(
          (widget) => widget is ChannelCarouselCard && widget.centered);
      expect(find.byType(ChannelCarouselCard), findsNWidgets(channelCount));
      expect(tester.widget<ChannelCarouselCard>(selected()).channelName,
          'Channel ${channelCount - 1}');
      expect(tester.getCenter(selected()).dx, closeTo(500, 0.01));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.byType(ChannelCarouselCard), findsNWidgets(channelCount));
      expect(tester.widget<ChannelCarouselCard>(selected()).channelName,
          'Channel 0');
      expect(tester.getCenter(selected()).dx, closeTo(500, 0.01));
    });
  }

  testWidgets('even exact-fit lineup scrolls while held paging advances by one',
      (tester) async {
    final centered = await pumpCarousel(tester, 4,
        initialIndex: 3, width: ChannelCarouselCard.cardPitch * 4);
    expect(find.byType(ListView), findsOneWidget);
    final selected = find.byWidgetPredicate(
        (widget) => widget is ChannelCarouselCard && widget.centered);
    expect(tester.getCenter(selected).dx, closeTo(500, 0.01));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(centered, [0, 1]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(tester.getCenter(selected).dx, closeTo(500, 0.01));
  });

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

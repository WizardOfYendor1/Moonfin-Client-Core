import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/livetv/live_tv_guide_screen.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

class _MockLiveTvApi extends Mock implements LiveTvApi {}

/// Deliberately asymmetric row shapes: differing programme durations give the
/// rows differing cell counts and boundaries, which is what makes a drifting
/// vertical move visible as a different cell index.
const _durations = <int>[20, 30, 45, 60, 180];

const _channelCount = 48;

/// One batch is 50 channels, so a lineup past that leaves the tail rows
/// genuinely unloaded — the only honest way to observe a loading row.
const _deferredChannelCount = 60;
const _firstDeferredChannelId = 'ch50';

/// The guide window the screen computes: today at the current hour, three
/// hours wide at the surface size these tests pump.
DateTime _windowStart() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, now.hour);
}

int _durationForRow(int row) => _durations[row % _durations.length];

/// The cell boundaries the screen derives for a row, in minutes from the
/// window start. Mirrors `buildRowCells` over a gapless fixture lineup.
int _cellIndexForRow(int row, int minutesFromWindowStart) =>
    minutesFromWindowStart ~/ _durationForRow(row);

int _minutesIntoRowCell(int row, int cellIndex) =>
    cellIndex * _durationForRow(row);

Map<String, dynamic> _channelRaw(int index) => <String, dynamic>{
  'Id': 'ch$index',
  'Name': 'Channel $index',
  'ChannelNumber': '${index + 1}',
  'ImageTags': <String, dynamic>{},
  'UserData': <String, dynamic>{'IsFavorite': false},
};

List<Map<String, dynamic>> _programsFor(String channelId) {
  final row = int.parse(channelId.substring(2));
  final duration = _durationForRow(row);
  final start = _windowStart();
  final programs = <Map<String, dynamic>>[];
  // Four hours of listings so the three-hour window is fully covered.
  for (var minute = 0; minute < 240; minute += duration) {
    programs.add(<String, dynamic>{
      'Id': '$channelId-p$minute',
      'ChannelId': channelId,
      'Name': '$channelId show $minute',
      'StartDate': start.add(Duration(minutes: minute)).toIso8601String(),
      'EndDate': start
          .add(Duration(minutes: minute + duration))
          .toIso8601String(),
    });
  }
  return programs;
}

/// Every focus node in the guide carries a debug label, which is the only
/// handle a test has on the rows' private nodes.
FocusNode _nodeLabelled(WidgetTester tester, String label) => tester
    .widgetList<Focus>(find.byType(Focus))
    .map((focus) => focus.focusNode)
    .whereType<FocusNode>()
    .firstWhere((node) => node.debugLabel == label);

String? _focusedLabel() => FocusManager.instance.primaryFocus?.debugLabel;

/// `(row, cellIndex)` of the focused programme cell, or null when focus is
/// somewhere else in the guide.
({int row, int index})? _focusedCell() {
  final label = _focusedLabel();
  if (label == null || !label.startsWith('GuideProgramRow')) return null;
  final parts = label.substring('GuideProgramRow'.length).split(':');
  return (row: int.parse(parts[0]), index: int.parse(parts[1]));
}

/// The horizontal scroll offsets of every horizontal scrollable in the guide
/// (the grid and the time header, which are kept in sync).
List<double> _horizontalOffsets(WidgetTester tester) => tester
    .stateList<ScrollableState>(find.byType(Scrollable))
    .where((state) => state.position.axis == Axis.horizontal)
    .map((state) => state.position.pixels)
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockMediaServerClient client;
  late _MockLiveTvApi liveTvApi;

  /// Overridable per test so a lineup can outgrow a single program batch.
  late int channelCount;

  /// When set, any guide request covering this channel is held open until the
  /// test releases it, so its row can be observed mid-load.
  String? deferredChannelId;
  late List<VoidCallback> releaseDeferredGuide;

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues(const {});
    final store = PreferenceStore();
    await store.init();
    GetIt.instance.registerSingleton<PreferenceStore>(store);
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));

    channelCount = _channelCount;
    deferredChannelId = null;
    releaseDeferredGuide = <VoidCallback>[];

    client = _MockMediaServerClient();
    liveTvApi = _MockLiveTvApi();
    when(() => client.liveTvApi).thenReturn(liveTvApi);
    when(() => client.userId).thenReturn('user');

    when(
      () => liveTvApi.getChannels(
        startIndex: any(named: 'startIndex'),
        limit: any(named: 'limit'),
        sortBy: any(named: 'sortBy'),
        sortOrder: any(named: 'sortOrder'),
        fields: any(named: 'fields'),
        enableTotalRecordCount: any(named: 'enableTotalRecordCount'),
        userId: any(named: 'userId'),
      ),
    ).thenAnswer(
      (_) async => <String, dynamic>{
        'Items': [for (var i = 0; i < channelCount; i++) _channelRaw(i)],
      },
    );

    when(
      () => liveTvApi.getGuide(
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
        channelIds: any(named: 'channelIds'),
        fields: any(named: 'fields'),
        enableTotalRecordCount: any(named: 'enableTotalRecordCount'),
        enableImages: any(named: 'enableImages'),
        enableUserData: any(named: 'enableUserData'),
        userId: any(named: 'userId'),
      ),
    ).thenAnswer((invocation) async {
      final ids =
          (invocation.namedArguments[#channelIds] as List?)?.cast<String>() ??
          const <String>[];
      final payload = <String, dynamic>{
        'Items': [for (final id in ids) ..._programsFor(id)],
      };
      final gate = deferredChannelId;
      if (gate == null || !ids.contains(gate)) return payload;

      final completer = Completer<Map<String, dynamic>>();
      releaseDeferredGuide.add(() => completer.complete(payload));
      return completer.future;
    });

    GetIt.instance.registerSingleton<MediaServerClient>(client);
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  Future<void> pumpGuide(
    WidgetTester tester, {
    bool miniPlayerMode = false,
  }) async {
    // Narrow enough that the three-hour window overflows the viewport, so a
    // horizontal offset can be non-zero and a stray scroll would show up.
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LiveTvGuideScreen(
          miniPlayerMode: miniPlayerMode,
          embedded: miniPlayerMode,
          onChannelSelected: miniPlayerMode ? (_) {} : null,
          onClose: miniPlayerMode ? () {} : null,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Focuses a row-0 cell two hours into the window and then steps right once,
  /// which is the only move permitted to rewrite the anchor. Returns the
  /// anchor's offset in minutes from the window start.
  Future<int> establishAnchor(WidgetTester tester) async {
    final seedIndex = _cellIndexForRow(0, 120);
    _nodeLabelled(tester, 'GuideProgramRow0:$seedIndex').requestFocus();
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    final focused = _focusedCell();
    expect(focused, isNotNull);
    expect(focused!.row, 0);
    return _minutesIntoRowCell(0, focused.index);
  }

  Future<void> pressDown(WidgetTester tester, int times) async {
    for (var i = 0; i < times; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
  }

  testWidgets('six DOWN presses leave the horizontal offset untouched', (
    tester,
  ) async {
    await pumpGuide(tester);
    await establishAnchor(tester);

    final before = _horizontalOffsets(tester);
    expect(before.any((offset) => offset > 0), isTrue);

    await pressDown(tester, 6);

    expect(_horizontalOffsets(tester), before);
  });

  testWidgets('forty-five DOWN presses leave the horizontal offset untouched', (
    tester,
  ) async {
    await pumpGuide(tester);
    await establishAnchor(tester);

    final before = _horizontalOffsets(tester);
    expect(before.any((offset) => offset > 0), isTrue);

    await pressDown(tester, 45);

    expect(_horizontalOffsets(tester), before);
  });

  testWidgets('every row visited selects the cell holding the anchor', (
    tester,
  ) async {
    await pumpGuide(tester);
    final anchorMinutes = await establishAnchor(tester);

    for (var step = 1; step <= 12; step++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      final focused = _focusedCell();
      expect(focused, isNotNull, reason: 'focus left the grid at step $step');
      expect(focused!.row, step);
      expect(
        focused.index,
        _cellIndexForRow(step, anchorMinutes),
        reason: 'row $step drifted away from the anchor',
      );
    }
  });

  testWidgets('focus is never null across a long vertical sequence', (
    tester,
  ) async {
    await pumpGuide(tester);
    await establishAnchor(tester);

    for (var i = 0; i < 20; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(_focusedCell(), isNotNull);
    }
    for (var i = 0; i < 20; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, isNotNull);
    }
  });

  testWidgets('landing on a clipped cell and on an oversized cell does not '
      'scroll', (tester) async {
    await pumpGuide(tester);
    final anchorMinutes = await establishAnchor(tester);
    final before = _horizontalOffsets(tester);

    // Row 3's hour-long cell around the anchor extends past the viewport's
    // right edge; row 4 is a single cell wider than the viewport.
    for (var step = 1; step <= 4; step++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(_horizontalOffsets(tester), before, reason: 'row $step scrolled');
    }

    final focused = _focusedCell();
    expect(focused, isNotNull);
    expect(focused!.row, 4);
    expect(focused.index, _cellIndexForRow(4, anchorMinutes));
  });

  /// Pumps a lineup one batch longer than the loader fetches, walks focus to
  /// the last loaded row (49), and leaves row 50's request outstanding.
  /// Returns the anchor's offset in minutes from the window start.
  Future<int> reachLoadedEdge(WidgetTester tester) async {
    channelCount = _deferredChannelCount;
    deferredChannelId = _firstDeferredChannelId;

    await pumpGuide(tester);
    final anchorMinutes = await establishAnchor(tester);
    await pressDown(tester, 49);

    final focused = _focusedCell();
    expect(focused, isNotNull);
    expect(focused!.row, 49, reason: 'did not reach the last loaded row');
    expect(
      releaseDeferredGuide,
      isNotEmpty,
      reason: 'the next batch was never requested, so no row is loading',
    );
    return anchorMinutes;
  }

  Future<void> releaseGuideData(WidgetTester tester) async {
    for (final release in releaseDeferredGuide) {
      release();
    }
    releaseDeferredGuide.clear();
    await tester.pumpAndSettle();
  }

  testWidgets('DOWN onto a loading row holds focus and consumes the key', (
    tester,
  ) async {
    final anchorMinutes = await reachLoadedEdge(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    final focused = _focusedCell();
    expect(focused, isNotNull, reason: 'focus left the grid');
    expect(focused!.row, 49);
    expect(focused.index, _cellIndexForRow(49, anchorMinutes));
  });

  testWidgets('a later UP supersedes the deferred DOWN', (tester) async {
    final anchorMinutes = await reachLoadedEdge(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_focusedCell()!.row, 49);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(_focusedCell()!.row, 48);

    await releaseGuideData(tester);

    final focused = _focusedCell();
    expect(focused, isNotNull);
    expect(focused!.row, 48, reason: 'the deferred DOWN fired anyway');
    expect(focused.index, _cellIndexForRow(48, anchorMinutes));
  });

  testWidgets('opening a dialog cancels the deferred DOWN', (tester) async {
    final anchorMinutes = await reachLoadedEdge(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_focusedCell()!.row, 49);

    // Select on the focused programme opens the details dialog.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    await releaseGuideData(tester);
    expect(
      _focusedCell(),
      isNull,
      reason: 'the deferred DOWN pulled focus back into the grid',
    );

    Navigator.of(tester.element(find.byType(AlertDialog))).pop();
    await tester.pumpAndSettle();

    final focused = _focusedCell();
    expect(focused, isNotNull);
    expect(focused!.row, 49, reason: 'the deferred DOWN fired after the dialog');
    expect(focused.index, _cellIndexForRow(49, anchorMinutes));
  });

  testWidgets('the deferred DOWN applies when the row data arrives', (
    tester,
  ) async {
    final anchorMinutes = await reachLoadedEdge(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_focusedCell()!.row, 49);

    await releaseGuideData(tester);

    final focused = _focusedCell();
    expect(focused, isNotNull, reason: 'the deferred DOWN never fired');
    expect(focused!.row, 50);
    expect(focused.index, _cellIndexForRow(50, anchorMinutes));
  });

  testWidgets('UP from row zero reaches the filter rail in standalone mode', (
    tester,
  ) async {
    await pumpGuide(tester);

    _nodeLabelled(tester, 'GuideProgramRow0:0').requestFocus();
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    expect(_focusedLabel(), 'GuideFilter:0');
  });

  testWidgets('UP from row zero reaches the mini player in miniPlayerMode', (
    tester,
  ) async {
    await pumpGuide(tester, miniPlayerMode: true);

    _nodeLabelled(tester, 'GuideProgramRow0:0').requestFocus();
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    expect(_focusedLabel(), 'GuideMiniPlayer');
  });
}

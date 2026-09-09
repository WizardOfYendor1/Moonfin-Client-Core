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

/// One batch is 50 channels; a lineup past that leaves the tail genuinely
/// unloaded, which is the only honest way to observe a loading cell.
const _deferredChannelCount = 60;
const _firstDeferredChannelId = 'ch50';

DateTime _windowStart() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, now.hour);
}

Map<String, dynamic> _channelRaw(String id, String name) => <String, dynamic>{
  'Id': id,
  'Name': name,
  'ChannelNumber': '1',
  'ImageTags': <String, dynamic>{},
  'UserData': <String, dynamic>{'IsFavorite': false},
};

Map<String, dynamic> _programRaw({
  required String id,
  required String channelId,
  required DateTime start,
  required DateTime end,
  bool isMovie = false,
}) => <String, dynamic>{
  'Id': id,
  'ChannelId': channelId,
  'Name': '$channelId show $id',
  'StartDate': start.toIso8601String(),
  'EndDate': end.toIso8601String(),
  'IsMovie': isMovie,
};

/// Every focus node in the guide carries a debug label, the only handle a
/// test has on the rows' private nodes. Shared convention with the other
/// guide widget tests.
FocusNode _nodeLabelled(WidgetTester tester, String label) => tester
    .widgetList<Focus>(find.byType(Focus))
    .map((focus) => focus.focusNode)
    .whereType<FocusNode>()
    .firstWhere((node) => node.debugLabel == label);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockMediaServerClient client;
  late _MockLiveTvApi liveTvApi;
  late List<Map<String, dynamic>> channels;
  late Map<String, List<Map<String, dynamic>>> programsByChannel;

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

    channels = <Map<String, dynamic>>[];
    programsByChannel = <String, List<Map<String, dynamic>>>{};
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
    ).thenAnswer((_) async => <String, dynamic>{'Items': channels});

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
        'Items': [
          for (final id in ids) ...(programsByChannel[id] ?? const []),
        ],
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
    ValueChanged<String>? onChannelSelected,
  }) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LiveTvGuideScreen(
          miniPlayerMode: true,
          embedded: true,
          onChannelSelected: onChannelSelected ?? (_) {},
          onClose: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a gap cell shows "No program data" and tunes the channel on press',
    (tester) async {
      final windowStart = _windowStart();
      channels = [_channelRaw('cGap', 'Channel Gap')];
      // Covers only the first hour; the rest of the three-hour window is a
      // genuine schedule gap, not a filtered-out show.
      programsByChannel['cGap'] = [
        _programRaw(
          id: 'cGap-p1',
          channelId: 'cGap',
          start: windowStart,
          end: windowStart.add(const Duration(minutes: 60)),
        ),
      ];
      String? tunedChannelId;

      await pumpGuide(tester, onChannelSelected: (id) => tunedChannelId = id);

      final l10n = AppLocalizations.of(
        tester.element(find.byType(LiveTvGuideScreen)),
      );
      expect(find.text(l10n.noProgramData), findsOneWidget);

      _nodeLabelled(tester, 'GuideProgramRow0:1').requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(tunedChannelId, 'cGap');
    },
  );

  testWidgets(
    'a filtered cell shows no "No program data" label and still tunes on '
    'press',
    (tester) async {
      final windowStart = _windowStart();
      channels = [_channelRaw('cFiltered', 'Channel Filtered')];
      // A movie for the first hour, then a non-movie for the rest; under the
      // Movies filter the second program's slot is a filtered hole, not a gap.
      programsByChannel['cFiltered'] = [
        _programRaw(
          id: 'p1',
          channelId: 'cFiltered',
          start: windowStart,
          end: windowStart.add(const Duration(minutes: 60)),
          isMovie: true,
        ),
        _programRaw(
          id: 'p2',
          channelId: 'cFiltered',
          start: windowStart.add(const Duration(minutes: 60)),
          end: windowStart.add(const Duration(hours: 3)),
        ),
      ];
      String? tunedChannelId;

      await pumpGuide(tester, onChannelSelected: (id) => tunedChannelId = id);

      final l10n = AppLocalizations.of(
        tester.element(find.byType(LiveTvGuideScreen)),
      );
      // Engages the Movies genre filter, which removes p2 and leaves a
      // filtered hole where it used to be.
      await tester.tap(find.text(l10n.movies));
      await tester.pumpAndSettle();

      expect(find.text(l10n.noProgramData), findsNothing);

      _nodeLabelled(tester, 'GuideProgramRow0:1').requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(tunedChannelId, 'cFiltered');
    },
  );

  testWidgets('a loading cell ignores a press', (tester) async {
    final windowStart = _windowStart();
    channels = [
      for (var i = 0; i < _deferredChannelCount; i++)
        _channelRaw('ch$i', 'Channel $i'),
    ];
    for (var i = 0; i < _deferredChannelCount; i++) {
      programsByChannel['ch$i'] = [
        _programRaw(
          id: 'ch$i-p1',
          channelId: 'ch$i',
          start: windowStart,
          end: windowStart.add(const Duration(hours: 3)),
        ),
      ];
    }
    deferredChannelId = _firstDeferredChannelId;
    String? tunedChannelId;

    await pumpGuide(tester, onChannelSelected: (id) => tunedChannelId = id);

    // Walk focus down to the first row of the second (unresolved) batch so
    // it is mounted, without waiting on its still-open request.
    _nodeLabelled(tester, 'GuideProgramRow0:0').requestFocus();
    await tester.pumpAndSettle();
    for (var i = 0; i < 49; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    expect(
      releaseDeferredGuide,
      isNotEmpty,
      reason: 'the second batch was never requested, so no row is loading',
    );

    final loadingNode = _nodeLabelled(tester, 'GuideProgramRow50:0');
    loadingNode.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(tunedChannelId, isNull);
    expect(find.byType(AlertDialog), findsNothing);
  });
}

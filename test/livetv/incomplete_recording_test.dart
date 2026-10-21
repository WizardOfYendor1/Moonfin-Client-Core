import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/auth/models/user.dart';
import 'package:moonfin/auth/repositories/user_repository.dart';
import 'package:moonfin/data/services/incomplete_recordings_service.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/detail/detail_buttons.dart';
import 'package:moonfin/ui/widgets/live_tv/incomplete_recording.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockClient extends Mock implements MediaServerClient {}

/// Answers the plugin's incomplete recordings endpoints from fields a test sets.
class _PluginAdapter implements HttpClientAdapter {
  List<Map<String, dynamic>> incomplete = [];
  int listStatus = 200;
  bool offline = false;
  int completeShowingStatus = 200;
  final requests = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add('${options.method} ${options.uri.path}');
    if (offline) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    if (options.uri.path.endsWith('/CompleteShowing')) {
      return ResponseBody.fromString('{}', completeShowingStatus, headers: _json);
    }
    if (listStatus != 200) return ResponseBody.fromString('', listStatus);
    return ResponseBody.fromString(jsonEncode(incomplete), 200, headers: _json);
  }

  static final _json = {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  };

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _incomplete(
  String id, {
  String? state,
  String? scheduledStart,
  String? recordedAt,
}) => {
  'itemId': id,
  'recordedMinutes': 23,
  'expectedMinutes': 37,
  'state': ?state,
  'scheduledStart': ?scheduledStart,
  'channelName': state == 'scheduled' ? 'KABC' : null,
  'recordedAt': ?recordedAt,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _PluginAdapter adapter;
  late IncompleteRecordingsService service;

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues(const {});
    final store = PreferenceStore();
    await store.init();
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));

    final client = _MockClient();
    when(() => client.baseUrl).thenReturn('http://server.test');
    when(() => client.accessToken).thenReturn('token');
    when(() => client.deviceInfo).thenReturn(
      const DeviceInfo(
        id: 'dev1',
        name: 'test',
        appName: 'moonfin',
        appVersion: '0.0.0',
      ),
    );

    adapter = _PluginAdapter();
    service = IncompleteRecordingsService(
      client: () => client,
      dio: Dio()..httpClientAdapter = adapter,
    );
    GetIt.instance.registerSingleton<IncompleteRecordingsService>(service);
  });

  tearDown(() async {
    service.dispose();
    await GetIt.instance.reset();
  });

  Future<void> load(List<Map<String, dynamic>> items) async {
    adapter.incomplete = items;
    service.setSupported(true);
    await service.refresh();
  }

  Widget app(Widget child) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  group('Record prompt', () {
    final start = DateTime(2026, 10, 22, 20);

    bool offers({
      Duration after = const Duration(minutes: 5),
      int? season = 3,
      int? episode = 7,
      bool supported = true,
      bool canManage = true,
    }) => offersCompleteShowing(
      programStart: start,
      now: start.add(after),
      season: season,
      episode: episode,
      supported: supported,
      canManage: canManage,
    );

    test('shows only past the start plus the grace minute', () {
      expect(offers(), isTrue);
      expect(offers(after: const Duration(seconds: 59)), isFalse);
      expect(offers(after: const Duration(minutes: -10)), isFalse);
    });

    test('needs season and episode numbers', () {
      expect(offers(season: null), isFalse);
      expect(offers(episode: null), isFalse);
    });

    test('needs the plugin and Live TV management', () {
      expect(offers(supported: false), isFalse);
      expect(offers(canManage: false), isFalse);
    });

    testWidgets('focuses the later-showing choice first', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );

      final result = showRecordPrompt(context: context, programName: 'Storage Wars');
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(context);
      expect(find.text('Storage Wars'), findsOneWidget);
      expect(find.text(l10n.recordPromptAlreadyStarted), findsOneWidget);
      final focused = FocusManager.instance.primaryFocus?.context;
      expect(
        focused == null
            ? null
            : find
                  .descendant(
                    of: find.byWidget(focused.widget),
                    matching: find.text(l10n.alsoRecordLaterShowing),
                  )
                  .evaluate()
                  .isNotEmpty,
        isTrue,
      );

      await tester.tap(find.text(l10n.justRecordNow));
      await tester.pumpAndSettle();
      expect(await result, RecordPromptChoice.justRecordNow);
    });

    Future<BuildContext> host(WidgetTester tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      return context;
    }

    void signIn({required bool canManageLiveTv}) {
      GetIt.instance.registerSingleton<UserRepository>(
        UserRepository()..setCurrentUser(
          PrivateUser(
            id: 'u1',
            name: 'User',
            serverId: 's1',
            accessToken: 't',
            lastUsed: DateTime(2026),
            canManageLiveTv: canManageLiveTv,
          ),
        ),
      );
    }

    Future<RecordAiringOutcome> record(
      BuildContext context,
      List<int> created,
    ) => recordAiring(
      context: context,
      programId: 'p1',
      programName: 'Storage Wars',
      programStart: DateTime.now().subtract(const Duration(minutes: 10)),
      rawProgram: const {'ParentIndexNumber': 3, 'IndexNumber': 7},
      createTimer: () async => created.add(1),
    );

    testWidgets('Back records nothing', (tester) async {
      signIn(canManageLiveTv: true);
      service.setSupported(true);
      final context = await host(tester);
      final created = <int>[];

      final outcome = record(context, created);
      await tester.pumpAndSettle();
      expect(find.text('Storage Wars'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(await outcome, RecordAiringOutcome.cancelled);
      expect(created, isEmpty);
    });

    testWidgets('the first choice records now and asks for a later showing', (tester) async {
      signIn(canManageLiveTv: true);
      service.setSupported(true);
      final context = await host(tester);
      final created = <int>[];

      final outcome = record(context, created);
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(AppLocalizations.of(context).alsoRecordLaterShowing),
      );
      await tester.pumpAndSettle();

      expect(await outcome, RecordAiringOutcome.recordedWithLaterShowing);
      expect(created, [1]);
      expect(adapter.requests, contains('POST /Moonfin/LiveTv/CompleteShowing'));
    });

    testWidgets('without Live TV management it records without asking', (tester) async {
      signIn(canManageLiveTv: false);
      service.setSupported(true);
      final context = await host(tester);
      final created = <int>[];

      final outcome = record(context, created);
      await tester.pumpAndSettle();

      expect(await outcome, RecordAiringOutcome.recorded);
      expect(created, [1]);
      expect(find.text('Storage Wars'), findsNothing);
    });
  });

  group('recording workflow messages', () {
    test('a failed later-showing request still reports the recording', () {
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(
        recordAiringMessage(l10n, RecordAiringOutcome.recordedLaterShowingFailed),
        "Recording started; couldn't request a later showing.",
      );
      expect(recordAiringMessage(l10n, RecordAiringOutcome.cancelled), isNull);
      expect(
        recordAiringMessage(l10n, RecordAiringOutcome.recorded),
        l10n.programSetToRecord,
      );
    });

    test('asking for a later showing reports a server refusal', () async {
      service.setSupported(true);
      adapter.completeShowingStatus = 404;
      expect(await askForLaterShowing('p1'), isFalse);
      adapter.completeShowingStatus = 200;
      expect(await askForLaterShowing('p1'), isTrue);
    });
  });

  group('service', () {
    test('reads the whole set in one call and matches ids with or without dashes', () async {
      await load([_incomplete('aa11bb22cc33dd44ee55ff6677889900')]);

      expect(service.stateFor('aa11bb22-cc33-dd44-ee55-ff6677889900'), isNotNull);
      expect(service.stateFor('somethingelse'), isNull);
      expect(
        adapter.requests.where((r) => r.endsWith('/Recordings/Incomplete')),
        hasLength(1),
      );
    });

    test('a refusal clears the set, an outage keeps it', () async {
      await load([_incomplete('item1')]);

      adapter.offline = true;
      await service.refresh();
      expect(service.stateFor('item1'), isNotNull);

      adapter.offline = false;
      adapter.listStatus = 403;
      await service.refresh();
      expect(service.stateFor('item1'), isNull);
    });

    test('without the plugin nothing is fetched or shown', () async {
      adapter.incomplete = [_incomplete('item1')];
      await service.refresh();

      expect(service.stateFor('item1'), isNull);
      expect(adapter.requests, isEmpty);
      expect(DetailButton.keepAsComplete.isOffered, isFalse);

      service.setSupported(true);
      await service.refresh();
      expect(DetailButton.keepAsComplete.isOffered, isTrue);
    });
  });

  group('badge and detail line', () {
    testWidgets('the badge draws only for an incomplete item', (tester) async {
      await load([_incomplete('item1')]);
      await tester.pumpWidget(
        app(
          const Column(
            children: [
              IncompleteRecordingBadge(itemId: 'item1'),
              IncompleteRecordingBadge(itemId: 'item2'),
            ],
          ),
        ),
      );

      expect(find.byType(IncompleteRecordingPill), findsOneWidget);
    });

    testWidgets('nothing draws without the plugin', (tester) async {
      adapter.incomplete = [_incomplete('item1')];
      await tester.pumpWidget(
        app(
          const Column(
            children: [
              IncompleteRecordingBadge(itemId: 'item1'),
              IncompleteRecordingDetailLine(itemId: 'item1'),
            ],
          ),
        ),
      );

      expect(find.byType(IncompleteRecordingPill), findsNothing);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('the detail line describes each state', (tester) async {
      await load([
        _incomplete(
          'scheduled',
          state: 'scheduled',
          scheduledStart: '2026-10-22T20:00:00Z',
        ),
        _incomplete(
          'recorded',
          state: 'recorded',
          recordedAt: '2026-10-22T20:00:00Z',
        ),
        _incomplete('notFound', state: 'notFound'),
        _incomplete('none'),
      ]);
      await tester.pumpWidget(
        app(
          const Column(
            children: [
              IncompleteRecordingDetailLine(itemId: 'scheduled'),
              IncompleteRecordingDetailLine(itemId: 'recorded'),
              IncompleteRecordingDetailLine(itemId: 'notFound'),
              IncompleteRecordingDetailLine(itemId: 'none'),
            ],
          ),
        ),
      );

      final lines = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data!)
          .toList();
      expect(lines, hasLength(4));
      expect(lines[0], startsWith('Incomplete · 23 of 37 min · Complete showing scheduled '));
      expect(lines[1], startsWith('Incomplete · 23 of 37 min · Complete copy recorded '));
      expect(lines[2], 'Incomplete · 23 of 37 min · No complete showing found');
      expect(lines[3], 'Incomplete · 23 of 37 min');
    });
  });
}

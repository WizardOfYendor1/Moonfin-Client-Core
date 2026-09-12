import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/viewmodels/live_tv_guide_view_model.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:server_core/server_core.dart';

class _MockClient extends Mock implements MediaServerClient {}

class _MockLiveTvApi extends Mock implements LiveTvApi {}

Map<String, dynamic> _channel(String id, {String? number}) => {
  'Id': id,
  'Name': 'Ch $id',
  'ChannelNumber': ?number,
};

Map<String, dynamic> _program(
  String id,
  String channelId, {
  bool isSports = false,
  bool isKids = false,
  bool isPremiere = false,
}) => {
  'Id': id,
  'ChannelId': channelId,
  'Name': 'Program $id',
  'StartDate': '2026-09-11T10:00:00Z',
  'EndDate': '2026-09-11T11:00:00Z',
  'IsSports': isSports,
  'IsKids': isKids,
  'IsPremiere': isPremiere,
};

/// The ChannelIds a stubbed getGuide call was made with.
List<String> _requestedIds(Invocation inv) =>
    (inv.namedArguments[#channelIds] as List<String>?) ?? const [];

/// Answers a sports request with one sports program per channel in the batch
/// that [isSports] says is a sports channel, mimicking a server-side flag.
Future<Map<String, dynamic>> Function(Invocation) _serverFiltered(
  bool Function(String id) isSports,
) => (inv) async => {
  'Items': [
    for (final id in _requestedIds(inv))
      if (isSports(id)) _program('p-$id', id, isSports: true),
  ],
};

/// A getGuide matcher. With no [category] every argument is wild-carded. With
/// one, the request must carry exactly that chip's genre flag and none of the
/// others (Premiere has no flag, so all five must be null).
Future<Map<String, dynamic>> _guide(
  LiveTvApi api, {
  GuideFilter? category,
  bool captureChannelIds = false,
}) {
  bool? flag(GuideFilter f, String name) =>
      category == null ? any(named: name) : (category == f ? true : null);
  return api.getGuide(
    startDate: any(named: 'startDate'),
    endDate: any(named: 'endDate'),
    channelIds: captureChannelIds
        ? captureAny(named: 'channelIds')
        : any(named: 'channelIds'),
    isMovie: flag(GuideFilter.movies, 'isMovie'),
    isSeries: flag(GuideFilter.series, 'isSeries'),
    isSports: flag(GuideFilter.sports, 'isSports'),
    isNews: flag(GuideFilter.news, 'isNews'),
    isKids: flag(GuideFilter.kids, 'isKids'),
    fields: any(named: 'fields'),
    enableTotalRecordCount: any(named: 'enableTotalRecordCount'),
    enableImages: any(named: 'enableImages'),
    enableUserData: any(named: 'enableUserData'),
    userId: any(named: 'userId'),
  );
}

void _stubChannels(LiveTvApi liveTv, List<Map<String, dynamic>> channels) {
  when(
    () => liveTv.getChannels(
      sortBy: any(named: 'sortBy'),
      sortOrder: any(named: 'sortOrder'),
      fields: any(named: 'fields'),
      enableTotalRecordCount: any(named: 'enableTotalRecordCount'),
      userId: any(named: 'userId'),
    ),
  ).thenAnswer((_) async => {'Items': channels});
}

void main() {
  late _MockClient client;
  late _MockLiveTvApi liveTv;

  setUp(() {
    client = _MockClient();
    liveTv = _MockLiveTvApi();
    when(() => client.liveTvApi).thenReturn(liveTv);
    when(() => client.userId).thenReturn('user');
    when(() => _guide(liveTv)).thenAnswer((_) async => {'Items': <dynamic>[]});
  });

  test(
    'load() fetches only the first batch; loadMorePrograms() paginates the rest',
    () async {
      // 120 channels → batches of 50 (never one giant all-channels request).
      _stubChannels(liveTv, List.generate(120, (i) => _channel('c$i')));

      final vm = LiveTvGuideViewModel(client);
      await vm.load();

      // Initial load requested exactly one batch of 50 channels, not all 120.
      final captured = verify(
        () => _guide(liveTv, captureChannelIds: true),
      ).captured;
      expect(captured.length, 1);
      expect((captured.single as List).length, 50);
      expect(vm.programsHighWater, 50);
      expect(vm.hasMorePrograms, isTrue);

      await vm.loadMorePrograms();
      expect(vm.programsHighWater, 100);
      expect(vm.hasMorePrograms, isTrue);

      await vm.loadMorePrograms();
      expect(vm.programsHighWater, 120);
      expect(vm.hasMorePrograms, isFalse);

      // Further calls are no-ops once every channel has been requested.
      await vm.loadMorePrograms();
      expect(vm.programsHighWater, 120);
    },
  );

  group('category filters', () {
    test(
      'a category chip asks the server for the lineup in flagged batches',
      () async {
        final channels = List.generate(
          120,
          (i) => _channel('c$i', number: '$i'),
        );
        _stubChannels(liveTv, channels);
        // Sports on channels well past the All view's first batch of 50, plus
        // a server that ignores the flag and returns a kids program.
        when(() => _guide(liveTv, category: GuideFilter.sports)).thenAnswer(
          (inv) async => {
            'Items': [
              for (final id in _requestedIds(inv))
                if (const {'c110', 'c7', 'c60'}.contains(id))
                  _program('p-$id', id, isSports: true),
              _program('p4', 'c8', isKids: true),
            ],
          },
        );

        final vm = LiveTvGuideViewModel(client);
        await vm.load();
        expect(vm.programsHighWater, 50);

        vm.setFilter(GuideFilter.sports);
        expect(vm.state, GuideState.loading);
        await Future<void>.delayed(Duration.zero);
        expect(vm.state, GuideState.ready);

        // 120 channels fit in one 200-channel batch: one request with every
        // channel id and only the sports flag set.
        final captured = verify(
          () => _guide(
            liveTv,
            category: GuideFilter.sports,
            captureChannelIds: true,
          ),
        ).captured;
        expect((captured.single as List).length, 120);

        // Channel-number order is kept (not response order), and c110 (row
        // 111) shows up even though only the first 50 channels had programs
        // loaded for the All view. The off-category kids program is dropped.
        expect(vm.filteredChannels.map((c) => c.id), ['c7', 'c60', 'c110']);
        expect(vm.hasProgramsFor('c110'), isTrue);
        expect(vm.programsForChannel('c110').single.id, 'p-c110');
        expect(vm.programsHighWater, 3);
        expect(vm.hasMorePrograms, isFalse);
      },
    );

    test('scrolling a category pulls the next batch of channels', () async {
      // 500 channels, every 10th one sports → 50 matching rows, 20 per batch.
      _stubChannels(
        liveTv,
        List.generate(500, (i) => _channel('c$i', number: '$i')),
      );
      when(() => _guide(liveTv, category: GuideFilter.sports)).thenAnswer(
        _serverFiltered((id) => int.parse(id.substring(1)) % 10 == 0),
      );

      final vm = LiveTvGuideViewModel(client);
      await vm.load();
      vm.setFilter(GuideFilter.sports);
      await Future<void>.delayed(Duration.zero);

      // The first page keeps walking until it has at least 24 rows: batch one
      // (c0–c199) gives 20, batch two (c200–c399) brings it to 40.
      final ids = vm.filteredChannels.map((c) => c.id).toList();
      expect(ids.length, 40);
      expect(ids.first, 'c0');
      expect(ids.last, 'c390');
      expect(vm.programsHighWater, 40);
      expect(vm.hasMorePrograms, isTrue);

      // Scrolling near the end asks for the rest of the lineup.
      await vm.loadMorePrograms();
      expect(vm.filteredChannels.length, 50);
      expect(vm.filteredChannels.last.id, 'c490');
      expect(vm.hasMorePrograms, isFalse);

      await vm.loadMorePrograms();
      expect(vm.filteredChannels.length, 50);
      verify(() => _guide(liveTv, category: GuideFilter.sports)).called(3);
    });

    test('re-sorting keeps category rows and only asks about unseen channels',
        () async {
      _stubChannels(
        liveTv,
        List.generate(500, (i) => _channel('c$i', number: '$i')),
      );
      when(() => _guide(liveTv, category: GuideFilter.sports)).thenAnswer(
        _serverFiltered((id) => int.parse(id.substring(1)) % 10 == 0),
      );

      final vm = LiveTvGuideViewModel(client);
      await vm.load();
      vm.setFilter(GuideFilter.sports);
      await Future<void>.delayed(Duration.zero);
      expect(vm.filteredChannels.length, 40); // c0–c399 walked
      clearInteractions(liveTv);

      vm.setSortBy(ChannelSortBy.name);
      await Future<void>.delayed(Duration.zero);

      // The 40 rows survive in the new order, and the walk that follows only
      // requests the 100 channels (c400–c499) it had not asked about yet.
      expect(vm.filteredChannels.length, 50);
      expect(vm.filteredChannels.first.name, 'Ch c0');
      expect(vm.hasMorePrograms, isFalse);
      final captured = verify(
        () => _guide(
          liveTv,
          category: GuideFilter.sports,
          captureChannelIds: true,
        ),
      ).captured;
      final requested = captured.expand((ids) => ids as List<String>).toSet();
      expect(requested.length, 100);
      expect(requested.every((id) => int.parse(id.substring(1)) >= 400), isTrue);
    });

    test('a sparse category keeps walking until it finds rows', () async {
      // Only the very last channel of 1000 is sports.
      _stubChannels(
        liveTv,
        List.generate(1000, (i) => _channel('c$i', number: '$i')),
      );
      when(() => _guide(liveTv, category: GuideFilter.sports)).thenAnswer(
        _serverFiltered((id) => id == 'c999'),
      );

      final vm = LiveTvGuideViewModel(client);
      await vm.load();
      vm.setFilter(GuideFilter.sports);
      await Future<void>.delayed(Duration.zero);

      expect(vm.state, GuideState.ready);
      expect(vm.filteredChannels.map((c) => c.id), ['c999']);
      expect(vm.hasMorePrograms, isFalse);
      verify(() => _guide(liveTv, category: GuideFilter.sports)).called(5);
    });

    test('premiere has no server flag, so it matches client-side', () async {
      _stubChannels(
        liveTv,
        List.generate(120, (i) => _channel('c$i', number: '$i')),
      );
      // Unflagged requests return every program; only c100's is a premiere.
      when(() => _guide(liveTv, category: GuideFilter.premiere)).thenAnswer(
        (inv) async => {
          'Items': [
            for (final id in _requestedIds(inv))
              _program('p-$id', id, isPremiere: id == 'c100'),
          ],
        },
      );

      final vm = LiveTvGuideViewModel(client);
      await vm.load();
      vm.setFilter(GuideFilter.premiere);
      await Future<void>.delayed(Duration.zero);

      expect(vm.filteredChannels.map((c) => c.id), ['c100']);
      expect(vm.programsForChannel('c100').single.id, 'p-c100');
      expect(vm.hasMorePrograms, isFalse);
    });

    test('switching chips drops a stale in-flight category response', () async {
      _stubChannels(liveTv, List.generate(10, (i) => _channel('c$i')));
      final sports = Completer<Map<String, dynamic>>();
      when(
        () => _guide(liveTv, category: GuideFilter.sports),
      ).thenAnswer((_) => sports.future);
      when(() => _guide(liveTv, category: GuideFilter.kids)).thenAnswer(
        (_) async => {
          'Items': [_program('k1', 'c3', isKids: true)],
        },
      );

      final vm = LiveTvGuideViewModel(client);
      await vm.load();

      vm.setFilter(GuideFilter.sports);
      vm.setFilter(GuideFilter.kids);
      await Future<void>.delayed(Duration.zero);
      expect(vm.state, GuideState.ready);
      expect(vm.filteredChannels.map((c) => c.id), ['c3']);

      // The slow sports response lands late and must not clobber Kids.
      sports.complete({
        'Items': [_program('s1', 'c1', isSports: true)],
      });
      await Future<void>.delayed(Duration.zero);
      expect(vm.filter, GuideFilter.kids);
      expect(vm.filteredChannels.map((c) => c.id), ['c3']);
    });

    test('backing out of a pending category returns to the All view', () async {
      _stubChannels(liveTv, List.generate(10, (i) => _channel('c$i')));
      final sports = Completer<Map<String, dynamic>>();
      when(
        () => _guide(liveTv, category: GuideFilter.sports),
      ).thenAnswer((_) => sports.future);

      final vm = LiveTvGuideViewModel(client);
      await vm.load();

      vm.setFilter(GuideFilter.sports);
      expect(vm.state, GuideState.loading);
      vm.setFilter(GuideFilter.all);
      expect(vm.state, GuideState.ready);
      expect(vm.filteredChannels.length, 10);

      sports.complete({'Items': <dynamic>[]});
      await Future<void>.delayed(Duration.zero);
      expect(vm.state, GuideState.ready);
      expect(vm.filteredChannels.length, 10);
    });

    test('shifting the window re-fetches the active category', () async {
      _stubChannels(liveTv, List.generate(10, (i) => _channel('c$i')));
      when(() => _guide(liveTv, category: GuideFilter.kids)).thenAnswer(
        (_) async => {
          'Items': [_program('k1', 'c5', isKids: true)],
        },
      );

      final vm = LiveTvGuideViewModel(client);
      await vm.load();
      vm.setFilter(GuideFilter.kids);
      await Future<void>.delayed(Duration.zero);

      await vm.shiftWindow(3);

      verify(() => _guide(liveTv, category: GuideFilter.kids)).called(2);
      expect(vm.filteredChannels.map((c) => c.id), ['c5']);
    });
  });
}

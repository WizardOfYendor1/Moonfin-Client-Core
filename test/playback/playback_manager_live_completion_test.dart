import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:playback_core/playback_core.dart';

/// A backend whose completion and error streams a test drives by hand, so the
/// manager sees exactly the end-of-stream report a live source produces.
class _TestBackend extends Fake implements PlayerBackend {
  final _errors = StreamController<Map<String, dynamic>>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final List<String> playedUrls = <String>[];
  int stopCalls = 0;
  int resumeLiveEdgeCalls = 0;
  /// Whether this engine can re-open a live source in place. False is the
  /// common case in the field -- only media3 can, and only for a source it
  /// was told is live -- and the manager must escalate rather than wait.
  bool canResumeLiveEdge = true;
  bool playing = false;
  Duration currentPosition = Duration.zero;
  Duration reportedDuration = Duration.zero;

  @override
  Duration get position => currentPosition;

  @override
  Duration get duration => reportedDuration;

  @override
  Duration get buffer => Duration.zero;

  @override
  bool get isPlaying => playing;

  @override
  bool? get playWhenReady => playing;

  @override
  double get playbackSpeed => 1.0;

  @override
  bool get isBuffering => false;

  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();

  @override
  Stream<Duration> get durationStream => const Stream<Duration>.empty();

  @override
  Stream<Duration> get bufferStream => const Stream<Duration>.empty();

  @override
  Stream<bool> get playingStream => _playing.stream;

  /// Reports the engine has resumed playing, e.g. after a live recovery.
  void emitPlaying() {
    playing = true;
    _playing.add(true);
  }

  @override
  Stream<bool> get bufferingStream => const Stream<bool>.empty();

  @override
  Stream<bool> get completedStream => _completed.stream;

  @override
  Stream<Map<String, dynamic>>? get errorStream => _errors.stream;

  void emitCompleted() => _completed.add(true);

  /// A generic mid-stream source failure, e.g. the HTTP 502 a live direct
  /// play gets when the upstream hiccups.
  void emitSourceError() => _errors.add(<String, dynamic>{
    'event': 'error',
    'errorCode': 2004,
    'message': 'Source error',
  });

  void emitLiveSourceReset() => _errors.add(<String, dynamic>{
    'event': 'playerError',
    'kind': 'live_source_reset',
    'recoverable': true,
    'message': 'Live source reset',
  });

  @override
  bool get supportsRuntimeTrackSelection => false;

  @override
  bool get canRenderBitmapSubtitles => false;

  @override
  bool get requiresStartupMediaReadyCheck => false;

  @override
  bool get nativelyHandlesStartPosition => true;

  @override
  Map<String, dynamic> getDeviceProfile({
    bool useProgressiveTranscode = false,
  }) => <String, dynamic>{};

  @override
  Future<void> play(
    dynamic mediaItem, {
    Duration startPosition = Duration.zero,
  }) async {
    playedUrls.add((mediaItem as Map<String, dynamic>)['url'] as String);
    currentPosition = startPosition;
    playing = true;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    playing = false;
  }

  @override
  Future<bool> resumeLiveEdge() async {
    resumeLiveEdgeCalls++;
    return canResumeLiveEdge;
  }

  @override
  Future<void> setSubtitleRendererMode(SubtitleRendererMode mode) async {}

  @override
  void dispose() {
    _errors.close();
    _completed.close();
    _playing.close();
  }
}

class _TestResolver extends MediaStreamResolver {
  int calls = 0;

  /// Whether the server hands back a live stream id. Off for the case where
  /// only the item's type says the channel is live.
  bool issueLiveStreamId = true;

  /// Records whether each resolve was allowed to direct play, so the
  /// escalation to a server transcode on the last attempt is observable.
  final List<bool> directPlayAllowed = <bool>[];

  @override
  Future<StreamResolutionResult> resolve(
    dynamic mediaItem, {
    Map<String, dynamic>? deviceProfile,
    int? maxStreamingBitrate,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    int? startTimeTicks,
    String? mediaSourceId,
    bool enableDirectPlay = true,
    bool enableDirectStream = true,
    bool enableTranscoding = true,
  }) async {
    calls++;
    directPlayAllowed.add(enableDirectPlay);
    final type = (mediaItem as Map<String, dynamic>)['Type'];
    final isLive = type == 'TvChannel' || type == 'LiveTvChannel';
    return StreamResolutionResult(
      streamUrl: 'https://example.test/session-$calls',
      mediaSourceId: 'source-$calls',
      liveStreamId: isLive && issueLiveStreamId ? 'live-$calls' : null,
      playSessionId: 'session-$calls',
      playMethod: StreamPlayMethod.transcode,
      mediaStreams: const [],
    );
  }
}

class _TestService implements PlayerService {
  final List<String> events = <String>[];
  final List<StreamResolutionResult> stoppedResolutions =
      <StreamResolutionResult>[];

  @override
  Future<void> onPlaybackStart(
    dynamic mediaItem,
    StreamResolutionResult resolution, {
    int? positionTicks,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    events.add('start:${resolution.playSessionId}');
  }

  @override
  Future<void> onPlaybackProgress(
    dynamic mediaItem,
    StreamResolutionResult resolution,
    Duration position, {
    bool isPaused = false,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    int? volumeLevel,
    bool? isMuted,
  }) async {}

  @override
  Future<void> onPlaybackStop(
    dynamic mediaItem,
    StreamResolutionResult resolution,
    Duration position,
  ) async {
    events.add('stop:${resolution.playSessionId}');
    stoppedResolutions.add(resolution);
  }

  @override
  Future<void> closeLiveStream(String liveStreamId) async {}

  @override
  Future<void> stopTranscoding(StreamResolutionResult resolution) async {}

  @override
  void dispose() {}
}

/// Drives the recovery budget's rolling window without waiting a minute.
class _Clock {
  DateTime now = DateTime(2026, 9, 15, 20);

  void advance(Duration by) => now = now.add(by);
}

PlaybackManager _manager(
  _TestBackend backend,
  _TestResolver resolver,
  _TestService service,
  _Clock clock,
) => PlaybackManager()
  ..setBackend(backend)
  ..setResolver(resolver)
  ..setPlayerService(service)
  ..clock = (() => clock.now);

/// The manager reads completion off a stream and recovers without awaiting,
/// so a test has to let those microtasks run before asserting.
Future<void> _settle() => pumpEventQueue(times: 40);

const _liveChannel = <String, dynamic>{
  'Id': 'channel-1',
  'Type': 'TvChannel',
  'Name': 'WKRC',
};

const _movie = <String, dynamic>{
  'Id': 'movie-1',
  'Type': 'Movie',
  'Name': 'A Film',
};

void main() {
  group('live end-of-stream never means finished', () {
    for (final autoAdvance in <bool>[true, false]) {
      test(
        'autoAdvance=$autoAdvance: a completed live item recovers instead of '
        'stopping',
        () async {
          final backend = _TestBackend();
          final resolver = _TestResolver();
          final service = _TestService();
          final clock = _Clock();
          final manager = _manager(backend, resolver, service, clock)
            ..autoAdvanceEnabled = autoAdvance;
          try {
            await manager.playItems(<dynamic>[_liveChannel]);
            backend.currentPosition = const Duration(seconds: 12);

            backend.emitCompleted();
            await _settle();

            expect(backend.resumeLiveEdgeCalls, 1);
            expect(backend.stopCalls, isZero);
            expect(service.stoppedResolutions, isEmpty);
            expect(resolver.calls, 1);
          } finally {
            manager.dispose();
          }
        },
      );
    }

    test('a channel known live only by its item type still recovers', () async {
      final backend = _TestBackend();
      final resolver = _TestResolver()..issueLiveStreamId = false;
      final service = _TestService();
      final clock = _Clock();
      final manager = _manager(backend, resolver, service, clock);
      try {
        await manager.playItems(<dynamic>[_liveChannel]);
        expect(manager.currentResolution?.liveStreamId, isNull);

        backend.emitCompleted();
        await _settle();

        expect(backend.resumeLiveEdgeCalls, 1);
        expect(service.stoppedResolutions, isEmpty);
      } finally {
        manager.dispose();
      }
    });

    test('a VOD stream the client outran recovers instead of parking', () async {
      final backend = _TestBackend();
      final resolver = _TestResolver();
      final service = _TestService();
      final clock = _Clock();
      final manager = _manager(backend, resolver, service, clock);
      try {
        await manager.playItems(<dynamic>[_movie]);
        // Ninety minutes long, the player gave up ten minutes in.
        backend.reportedDuration = const Duration(minutes: 90);
        backend.currentPosition = const Duration(minutes: 10);
        // Past the settle window that ignores a completion right after start.
        clock.advance(const Duration(seconds: 30));

        backend.emitCompleted();
        await _settle();

        // It used to do nothing at all and leave the player on its last frame.
        expect(backend.resumeLiveEdgeCalls, 1);
        expect(service.stoppedResolutions, isEmpty);
      } finally {
        manager.dispose();
      }
    });

    test('a finished VOD item still stops and reports', () async {
      final backend = _TestBackend();
      final resolver = _TestResolver();
      final service = _TestService();
      final clock = _Clock();
      final manager = _manager(backend, resolver, service, clock)
        ..autoAdvanceEnabled = false;
      try {
        await manager.playItems(<dynamic>[_movie]);
        backend.reportedDuration = const Duration(minutes: 90);
        backend.currentPosition = const Duration(minutes: 90);

        backend.emitCompleted();
        await _settle();

        expect(backend.resumeLiveEdgeCalls, isZero);
        expect(service.stoppedResolutions, hasLength(1));
      } finally {
        manager.dispose();
      }
    });
  });

  group('recovery budget', () {
    test('escalates resume, re-resolve, server stream, then gives up', () async {
      final backend = _TestBackend();
      final resolver = _TestResolver();
      final service = _TestService();
      final clock = _Clock();
      final manager = _manager(backend, resolver, service, clock);
      final sessionEnded = <void>[];
      final sub = manager.sessionEndedStream.listen(sessionEnded.add);
      try {
        await manager.playItems(<dynamic>[_liveChannel]);

        for (var i = 0; i < 4; i++) {
          clock.advance(const Duration(seconds: 5));
          backend.emitCompleted();
          await _settle();
        }

        expect(backend.resumeLiveEdgeCalls, 1);
        // Attempt two re-resolves on the fast direct route; only attempt
        // three, the last thing tried before the channel is given up, hands
        // the stream to the server.
        expect(resolver.calls, 3);
        expect(resolver.directPlayAllowed, <bool>[true, true, false]);
        expect(backend.playedUrls, <String>[
          'https://example.test/session-1',
          'https://example.test/session-2',
          'https://example.test/session-3',
        ]);
        // The fourth event is terminal: the tuner is released and the
        // bringup is reported failed, which is how this manager says a stream
        // could not be played.
        expect(service.stoppedResolutions, isNotEmpty);
        expect(manager.bringupState.phase, PlaybackBringupPhase.failed);
        expect(manager.bringupState.error, liveStreamLostError);
        // A dead channel is a failure, not a finished queue.
        expect(sessionEnded, isEmpty);
      } finally {
        await sub.cancel();
        manager.dispose();
      }
    });

    test('a second completion inside the debounce window is ignored', () async {
      final backend = _TestBackend();
      final resolver = _TestResolver();
      final service = _TestService();
      final clock = _Clock();
      final manager = _manager(backend, resolver, service, clock);
      try {
        await manager.playItems(<dynamic>[_liveChannel]);

        backend.emitCompleted();
        await _settle();
        clock.advance(const Duration(milliseconds: 200));
        backend.emitCompleted();
        await _settle();

        expect(backend.resumeLiveEdgeCalls, 1);
      } finally {
        manager.dispose();
      }
    });

    test('a quiet minute gives the budget back', () async {
      final backend = _TestBackend();
      final resolver = _TestResolver();
      final service = _TestService();
      final clock = _Clock();
      final manager = _manager(backend, resolver, service, clock);
      try {
        await manager.playItems(<dynamic>[_liveChannel]);

        for (var i = 0; i < 6; i++) {
          clock.advance(const Duration(seconds: 90));
          backend.emitCompleted();
          await _settle();
        }

        // Every hiccup sat a clear minute past the last, so each one is the
        // first attempt of a fresh budget and none of them escalates.
        expect(backend.resumeLiveEdgeCalls, 6);
        expect(service.stoppedResolutions, isEmpty);
        expect(resolver.calls, 1);
      } finally {
        manager.dispose();
      }
    });

    test('a live source reset shares the budget and skips the cheap tier', () async {
      final backend = _TestBackend();
      final resolver = _TestResolver();
      final service = _TestService();
      final clock = _Clock();
      final manager = _manager(backend, resolver, service, clock);
      final sessionEnded = <void>[];
      final sub = manager.sessionEndedStream.listen(sessionEnded.add);
      try {
        await manager.playItems(<dynamic>[_liveChannel]);

        for (var i = 0; i < 4; i++) {
          clock.advance(const Duration(seconds: 5));
          backend.emitLiveSourceReset();
          await _settle();
        }

        // Re-opening a reset source in place cannot help, so all three
        // attempts re-resolve, and the fourth event is still terminal.
        expect(backend.resumeLiveEdgeCalls, isZero);
        expect(resolver.calls, 4);
        expect(manager.bringupState.phase, PlaybackBringupPhase.failed);
      } finally {
        await sub.cancel();
        manager.dispose();
      }
    });

    test('retuning the channel restores the whole budget', () async {
      final backend = _TestBackend();
      final resolver = _TestResolver();
      final service = _TestService();
      final clock = _Clock();
      final manager = _manager(backend, resolver, service, clock);
      try {
        await manager.playItems(<dynamic>[_liveChannel]);
        for (var i = 0; i < 4; i++) {
          clock.advance(const Duration(seconds: 5));
          backend.emitCompleted();
          await _settle();
        }
        expect(service.stoppedResolutions, isNotEmpty);
        final resumesBeforeRetry = backend.resumeLiveEdgeCalls;

        // What Retry on the channel-lost card does.
        await manager.playItems(<dynamic>[_liveChannel]);
        clock.advance(const Duration(seconds: 5));
        backend.emitCompleted();
        await _settle();

        // A cheap resume, not the terminal step a spent budget would give.
        expect(backend.resumeLiveEdgeCalls, resumesBeforeRetry + 1);
      } finally {
        manager.dispose();
      }
    });

    test('a live source error recovers instead of killing the channel', () async {
      final backend = _TestBackend();
      final resolver = _TestResolver();
      final service = _TestService();
      final clock = _Clock();
      final manager = _manager(backend, resolver, service, clock);
      try {
        await manager.playItems(<dynamic>[_liveChannel]);

        backend.emitSourceError();
        await _settle();

        // One bad response is a hiccup, not a dead channel.
        expect(backend.resumeLiveEdgeCalls, 1);
        expect(manager.bringupState.phase, isNot(PlaybackBringupPhase.failed));
        expect(service.stoppedResolutions, isEmpty);
      } finally {
        manager.dispose();
      }
    });

    test('a VOD source error still fails the bringup', () async {
      final backend = _TestBackend();
      final resolver = _TestResolver();
      final service = _TestService();
      final clock = _Clock();
      final manager = _manager(backend, resolver, service, clock);
      try {
        await manager.playItems(<dynamic>[_movie]);

        backend.emitSourceError();
        await _settle();

        expect(backend.resumeLiveEdgeCalls, isZero);
        expect(manager.bringupState.phase, PlaybackBringupPhase.failed);
      } finally {
        manager.dispose();
      }
    });

    test('repeated live source errors still give up in the end', () async {
      final backend = _TestBackend();
      final resolver = _TestResolver();
      final service = _TestService();
      final clock = _Clock();
      final manager = _manager(backend, resolver, service, clock);
      try {
        await manager.playItems(<dynamic>[_liveChannel]);

        for (var i = 0; i < 5; i++) {
          clock.advance(const Duration(seconds: 5));
          backend.emitSourceError();
          await _settle();
        }

        expect(manager.bringupState.phase, PlaybackBringupPhase.failed);
        expect(manager.bringupState.error, liveStreamLostError);
      } finally {
        manager.dispose();
      }
    });

    test('completions and source resets cannot exceed one budget', () async {
      final backend = _TestBackend();
      final resolver = _TestResolver();
      final service = _TestService();
      final clock = _Clock();
      final manager = _manager(backend, resolver, service, clock);
      final sessionEnded = <void>[];
      final sub = manager.sessionEndedStream.listen(sessionEnded.add);
      try {
        await manager.playItems(<dynamic>[_liveChannel]);

        for (var i = 0; i < 6; i++) {
          clock.advance(const Duration(seconds: 5));
          if (i.isEven) {
            backend.emitCompleted();
          } else {
            backend.emitLiveSourceReset();
          }
          await _settle();
        }

        // Three recoveries, then terminal, and nothing after it revives the
        // channel: six events must not buy six attempts.
        expect(backend.resumeLiveEdgeCalls, lessThanOrEqualTo(1));
        expect(manager.bringupState.phase, PlaybackBringupPhase.failed);
      } finally {
        await sub.cancel();
        manager.dispose();
      }
    });
  });

  group('live recovery status', () {
    test('reports attempt 1 of 3 on the first recovery', () async {
      final backend = _TestBackend();
      final resolver = _TestResolver();
      final service = _TestService();
      final clock = _Clock();
      final manager = _manager(backend, resolver, service, clock);
      final statuses = <LiveRecoveryStatus?>[];
      final sub = manager.liveRecoveryStatusStream.listen(statuses.add);
      try {
        await manager.playItems(<dynamic>[_liveChannel]);

        backend.emitCompleted();
        await _settle();

        expect(manager.liveRecoveryStatus?.attempt, 1);
        expect(manager.liveRecoveryStatus?.maxAttempts, 3);
        expect(statuses.whereType<LiveRecoveryStatus>().length, 1);
      } finally {
        await sub.cancel();
        manager.dispose();
      }
    });

    test('advances with further attempts', () async {
      final backend = _TestBackend()..canResumeLiveEdge = false;
      final resolver = _TestResolver();
      final service = _TestService();
      final clock = _Clock();
      final manager = _manager(backend, resolver, service, clock);
      try {
        await manager.playItems(<dynamic>[_liveChannel]);

        for (var i = 0; i < 3; i++) {
          clock.advance(const Duration(seconds: 5));
          backend.emitCompleted();
          await _settle();
          expect(manager.liveRecoveryStatus?.attempt, i + 1);
          expect(manager.liveRecoveryStatus?.maxAttempts, 3);
        }
      } finally {
        manager.dispose();
      }
    });

    test('clears when the backend reports playing', () async {
      final backend = _TestBackend();
      final resolver = _TestResolver();
      final service = _TestService();
      final clock = _Clock();
      final manager = _manager(backend, resolver, service, clock);
      try {
        await manager.playItems(<dynamic>[_liveChannel]);

        backend.emitCompleted();
        await _settle();
        expect(manager.liveRecoveryStatus, isNotNull);

        backend.emitPlaying();
        await _settle();

        expect(manager.liveRecoveryStatus, isNull);
      } finally {
        manager.dispose();
      }
    });

    test('clears on give-up, alongside the failed bringup state', () async {
      final backend = _TestBackend();
      final resolver = _TestResolver();
      final service = _TestService();
      final clock = _Clock();
      final manager = _manager(backend, resolver, service, clock);
      try {
        await manager.playItems(<dynamic>[_liveChannel]);

        for (var i = 0; i < 5; i++) {
          clock.advance(const Duration(seconds: 5));
          backend.emitCompleted();
          await _settle();
        }

        expect(manager.bringupState.phase, PlaybackBringupPhase.failed);
        expect(manager.liveRecoveryStatus, isNull);
      } finally {
        manager.dispose();
      }
    });

    test('clears when the viewer stops playback', () async {
      final backend = _TestBackend();
      final resolver = _TestResolver();
      final service = _TestService();
      final clock = _Clock();
      final manager = _manager(backend, resolver, service, clock);
      try {
        await manager.playItems(<dynamic>[_liveChannel]);

        backend.emitCompleted();
        await _settle();
        expect(manager.liveRecoveryStatus, isNotNull);

        await manager.stop();

        expect(manager.liveRecoveryStatus, isNull);
      } finally {
        manager.dispose();
      }
    });

    test('clears when the viewer tunes to another channel', () async {
      final backend = _TestBackend();
      final resolver = _TestResolver();
      final service = _TestService();
      final clock = _Clock();
      final manager = _manager(backend, resolver, service, clock);
      try {
        await manager.playItems(<dynamic>[_liveChannel]);

        backend.emitCompleted();
        await _settle();
        expect(manager.liveRecoveryStatus, isNotNull);

        await manager.playItems(<dynamic>[
          <String, dynamic>{
            'Id': 'channel-2',
            'Type': 'TvChannel',
            'Name': 'WXIX',
          },
        ]);

        expect(manager.liveRecoveryStatus, isNull);
      } finally {
        manager.dispose();
      }
    });
  });
}

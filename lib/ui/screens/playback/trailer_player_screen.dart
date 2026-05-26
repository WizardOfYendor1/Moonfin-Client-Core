import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../data/services/youtube_stream_resolver.dart';
import '../../../l10n/app_localizations.dart';
import '../../../util/platform_detection.dart';
import '../../widgets/web_youtube_trailer.dart';

class TrailerPlayerScreen extends StatefulWidget {
  final String? videoId;
  final String? trailerUrl;

  const TrailerPlayerScreen({super.key, this.videoId, this.trailerUrl});

  @override
  State<TrailerPlayerScreen> createState() => _TrailerPlayerScreenState();
}

class _TrailerPlayerScreenState extends State<TrailerPlayerScreen> {
  static const _openTimeout = Duration(seconds: 12);
  static const _resolveTimeout = Duration(seconds: 10);

  Player? _player;
  VideoController? _controller;
  bool _loading = true;
  String? _error;
  String? _webVideoId;
  bool _useEmbeddedYouTube = false;
  bool _embedFallbackTriggered = false;

  void _debugLog(String message) {
    if (!kDebugMode) return;
    debugPrint('[TrailerPlayerScreen] $message');
  }

  bool get _supportsEmbeddedYouTubePlatform {
    return PlatformDetection.isAndroid ||
        PlatformDetection.isIOS ||
        PlatformDetection.isMacOS;
  }

  @override
  void initState() {
    super.initState();
    final resolvedVideoId = _resolvedVideoId();
    _debugLog('init videoId=${widget.videoId} trailerUrl=${widget.trailerUrl} resolvedVideoId=$resolvedVideoId supportsEmbedded=$_supportsEmbeddedYouTubePlatform isWeb=$kIsWeb');

    if (kIsWeb) {
      if (resolvedVideoId == null || resolvedVideoId.isEmpty) {
        _error = AppLocalizations.of(context).unableToLoadTrailerStream;
      } else {
        _webVideoId = resolvedVideoId;
      }
      _loading = false;
      return;
    }

    if (_supportsEmbeddedYouTubePlatform &&
        resolvedVideoId != null &&
        resolvedVideoId.isNotEmpty) {
      _useEmbeddedYouTube = true;
      _webVideoId = resolvedVideoId;
      _loading = true;
      return;
    }

    _startStreamPlaybackPath();
  }

  String? _resolvedVideoId() {
    final videoId = widget.videoId;
    if (videoId != null && videoId.isNotEmpty) {
      return videoId;
    }
    final trailerUrl = widget.trailerUrl;
    if (trailerUrl == null || trailerUrl.isEmpty) {
      return null;
    }
    return YouTubeStreamResolver.extractVideoId(trailerUrl);
  }

  void _startStreamPlaybackPath() {
    _debugLog('start stream playback path');
    _player ??= Player(
      configuration: const PlayerConfiguration(libass: false),
    );
    _controller ??= VideoController(
      _player!,
      configuration: VideoControllerConfiguration(
        hwdec: PlatformDetection.isLinux ? 'auto-safe' : null,
      ),
    );
    unawaited(_openTrailer());
  }

  void _onEmbeddedPlaybackStarted() {
    _debugLog('embedded playback started callback');
    if (!mounted || !_loading) {
      return;
    }
    setState(() => _loading = false);
  }

  void _fallBackToStreamPlayback() {
    if (_embedFallbackTriggered || !_useEmbeddedYouTube) {
      return;
    }
    _debugLog('embedded fallback triggered -> stream playback');
    _embedFallbackTriggered = true;
    setState(() {
      _useEmbeddedYouTube = false;
      _error = null;
      _loading = true;
    });
    _startStreamPlaybackPath();
  }

  @override
  void dispose() {
    _player?.stop();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _openTrailer() async {
    String? streamUrl;
    bool useYouTubeHeaders = false;

    if (widget.videoId != null && widget.videoId!.isNotEmpty) {
      _debugLog('resolving stream from videoId=${widget.videoId}');
      streamUrl = await YouTubeStreamResolver
          .resolve(widget.videoId!)
          .timeout(_resolveTimeout, onTimeout: () => null);
      if (streamUrl != null && streamUrl.isNotEmpty) {
        useYouTubeHeaders = true;
        _debugLog('resolved direct videoId stream url');
      } else {
        streamUrl = 'https://www.youtube.com/watch?v=${widget.videoId!}';
        useYouTubeHeaders = false;
        _debugLog('resolver failed for videoId, fallback to watch url');
      }
    } else if (widget.trailerUrl != null && widget.trailerUrl!.isNotEmpty) {
      final trailerUrl = widget.trailerUrl!;
      final youtubeVideoId = YouTubeStreamResolver.extractVideoId(trailerUrl);
      _debugLog('resolving stream from trailerUrl youtubeVideoId=$youtubeVideoId');
      streamUrl = await YouTubeStreamResolver
          .resolveFromUrl(trailerUrl)
          .timeout(_resolveTimeout, onTimeout: () => null);
      if (streamUrl != null && streamUrl.isNotEmpty) {
        useYouTubeHeaders = youtubeVideoId != null;
        _debugLog('resolved trailerUrl stream useYouTubeHeaders=$useYouTubeHeaders');
      } else {
        streamUrl = trailerUrl;
        useYouTubeHeaders = false;
        _debugLog('resolver failed for trailerUrl, fallback to raw trailer url');
      }
    }

    if (!mounted) return;

    if (streamUrl == null || streamUrl.isEmpty) {
      _debugLog('open trailer aborted: no stream url');
      final l10n = AppLocalizations.of(context);
      setState(() {
        _loading = false;
        _error = l10n.unableToLoadTrailerStream;
      });
      return;
    }

    try {
      _debugLog('opening stream useYouTubeHeaders=$useYouTubeHeaders');
      final media = useYouTubeHeaders
          ? Media(streamUrl, httpHeaders: YouTubeStreamResolver.youtubeHeaders)
          : Media(streamUrl);
      await _player!.open(media).timeout(_openTimeout);
      if (!mounted) return;
      _debugLog('stream open succeeded');
      setState(() {
        _loading = false;
      });
    } on TimeoutException {
      _debugLog('stream open timed out after $_openTimeout');
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      setState(() {
        _loading = false;
        _error = l10n.trailerTimedOut;
      });
    } catch (error) {
      _debugLog('stream open failed: $error');
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      setState(() {
        _loading = false;
        _error = l10n.playbackFailedForTrailer;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black,
              child: ((kIsWeb || _useEmbeddedYouTube) && _webVideoId != null)
                  ? Center(
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: WebYouTubeTrailer(
                          videoId: _webVideoId!,
                          muted: false,
                          loop: false,
                          onPlaybackStarted: _onEmbeddedPlaybackStarted,
                          onEmbeddedUnavailable: _useEmbeddedYouTube
                              ? _fallBackToStreamPlayback
                              : null,
                          onAutoplayFailed: _useEmbeddedYouTube
                              ? _fallBackToStreamPlayback
                              : null,
                        ),
                      ),
                    )
                  : (_controller != null
                        ? Video(
                            controller: _controller!,
                            controls: AdaptiveVideoControls,
                            fit: BoxFit.contain,
                            pauseUponEnteringBackgroundMode: false,
                            fill: Colors.black,
                          )
                        : const SizedBox.shrink()),
            ),
          ),
          if (_loading)
            const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () {
                    _player?.stop();
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

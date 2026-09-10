import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';

import '../../../data/viewmodels/live_tv_guide_view_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../screens/livetv/epg/epg_genre.dart';
import '../../screens/livetv/guide/guide_window.dart';
import 'channel_carousel.dart';
import 'channel_carousel_card.dart';

/// Owns the carousel's guide data and timers while video remains behind it.
class ChannelCarouselOverlay extends StatefulWidget {
  final MediaServerClient client;
  final List<GuideChannel> channels;
  final String currentChannelId;
  final int selectionRevision;
  final ValueChanged<String> onChannelSelected;
  final VoidCallback onDismiss;
  final VoidCallback onShowControls;
  final Duration inactivityDuration;
  final LiveTvGuideViewModel Function(MediaServerClient)? viewModelFactory;

  const ChannelCarouselOverlay({
    super.key,
    required this.client,
    required this.channels,
    required this.currentChannelId,
    this.selectionRevision = 0,
    required this.onChannelSelected,
    required this.onDismiss,
    required this.onShowControls,
    this.inactivityDuration = const Duration(minutes: 2),
    this.viewModelFactory,
  });

  @override
  State<ChannelCarouselOverlay> createState() => _ChannelCarouselOverlayState();
}

class _ChannelCarouselOverlayState extends State<ChannelCarouselOverlay>
    with WidgetsBindingObserver {
  static const _debounce = Duration(milliseconds: 300);

  /// How often live progress and the current programme are re-evaluated.
  static const _clockTick = Duration(seconds: 15);

  /// Roughly a third shorter than the original 150: tighter padding and
  /// leading and a one-step-smaller title, with both overview lines kept.
  static const double _headerHeight = 104;
  late final LiveTvGuideViewModel _vm;
  late List<GuideChannel> _channels;

  /// Presentation entries, recomputed only when the guide data or the clock
  /// moves. Building them per frame made every debounced `setState` walk the
  /// whole lineup, reformatting times and image URLs it already had.
  List<ChannelCarouselEntry> _entries = const [];
  bool _entriesDirty = true;
  late String _centeredId;
  Timer? _headerTimer;
  Timer? _loadTimer;
  Timer? _hideTimer;
  Timer? _clockTimer;
  Timer? _quarterTimer;
  GuideProgram? _headerProgram;
  GuideChannel? _headerChannel;
  int _visibleCards = 5;
  bool _scrolling = false;
  bool _ready = false;
  bool _dismissed = false;
  bool _loadingVisible = false;
  bool _loadAgain = false;
  final FocusNode _overlayFocus = FocusNode(
    debugLabel: 'ChannelCarouselOverlay',
  );

  @override
  void initState() {
    super.initState();
    _vm =
        widget.viewModelFactory?.call(widget.client) ??
        LiveTvGuideViewModel(widget.client);
    _channels = List.of(widget.channels)
      ..sort(LiveTvGuideViewModel.comparatorFor(_vm.sortBy));
    _centeredId = widget.currentChannelId;
    if (_channels.isNotEmpty &&
        !_channels.any((channel) => channel.id == _centeredId)) {
      _centeredId = _channels.first.id;
    }
    _vm.addListener(_onDataChanged);
    WidgetsBinding.instance.addObserver(this);
    _resetInactivity();
    _vm.scheduleBoundaryRefresh();
    _clockTimer = Timer.periodic(_clockTick, (_) {
      if (mounted) setState(_invalidateEntries);
    });
    _scheduleQuarterRefresh();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _overlayFocus.canRequestFocus) {
        _overlayFocus.requestFocus();
      }
    });
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _invalidateEntries();
  }

  @override
  void didUpdateWidget(covariant ChannelCarouselOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentChannelId == widget.currentChannelId &&
        oldWidget.selectionRevision == widget.selectionRevision) {
      return;
    }
    if (!_channels.any((channel) => channel.id == widget.currentChannelId)) {
      return;
    }
    _centeredId = widget.currentChannelId;
    _scheduleHeader();
    _scheduleVisibleLoad();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _headerTimer?.cancel();
    _loadTimer?.cancel();
    _hideTimer?.cancel();
    _clockTimer?.cancel();
    _quarterTimer?.cancel();
    _vm.removeListener(_onDataChanged);
    _vm.cancelBoundaryRefresh();
    _vm.dispose();
    _overlayFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _vm.scheduleBoundaryRefresh();
      _scheduleQuarterRefresh();
      _scheduleHeader();
      setState(_invalidateEntries);
    }
  }

  Future<void> _load() async {
    await _vm.load(
      initialChannelIds: _neighborhood(),
      windowStart: guideLeftEdge(DateTime.now()),
      livePosition: true,
    );
    if (!mounted) return;
    final playbackIds = widget.channels.map((channel) => channel.id).toSet();
    setState(() {
      _channels = _vm.filteredChannels
          .where((channel) => playbackIds.contains(channel.id))
          .toList();
      _ready = true;
      if (_channels.isNotEmpty &&
          !_channels.any((channel) => channel.id == _centeredId)) {
        _centeredId = _channels.first.id;
      }
      _invalidateEntries();
    });
    if (_channels.isEmpty) {
      _dismiss();
      return;
    }
    _vm.scheduleBoundaryRefresh();
    _scheduleHeader();
    _scheduleVisibleLoad();
  }

  List<String> _neighborhood() {
    if (_channels.isEmpty) return const [];
    final center = math.max(
      0,
      _channels.indexWhere((channel) => channel.id == _centeredId),
    );
    final radius = (_visibleCards / 2).ceil() + 1;
    return {
      for (var offset = -radius; offset <= radius; offset++)
        _channels[(center + offset) % _channels.length].id,
    }.toList();
  }

  void _onDataChanged() {
    if (!mounted) return;
    setState(_invalidateEntries);
    if (_ready) _scheduleHeader();
  }

  void _invalidateEntries() => _entriesDirty = true;

  /// Rebuilt lazily from `build`, where localisations are available, with one
  /// `now` for the whole lineup. The list identity is stable between data
  /// changes, which is what lets the strip reuse its card widgets.
  List<ChannelCarouselEntry> get _currentEntries {
    if (!_entriesDirty) return _entries;
    _entriesDirty = false;
    // Quantised to the clock tick that is meant to refresh the strip, so a
    // rebuild between ticks produces entries equal to the ones it replaces.
    final now = _tickAlignedNow();
    var changed = _entries.length != _channels.length;
    final next = <ChannelCarouselEntry>[];
    for (var i = 0; i < _channels.length; i++) {
      final fresh = _entry(_channels[i], now);
      final previous = i < _entries.length ? _entries[i] : null;
      if (previous != null && previous == fresh) {
        next.add(previous);
      } else {
        changed = true;
        next.add(fresh);
      }
    }
    // An unchanged lineup keeps its list identity, which is what lets the
    // strip reuse every built card instead of rebuilding the visible run.
    if (changed) _entries = next;
    return _entries;
  }

  static DateTime _tickAlignedNow() {
    final now = DateTime.now();
    final seconds = now.second - now.second % _clockTick.inSeconds;
    return DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
      seconds,
    );
  }

  void _centered(int index) {
    _centeredId = _channels[index].id;
    _scheduleHeader();
    _scheduleVisibleLoad();
  }

  /// A hold repeats faster than [_debounce], so a sustained one would never
  /// let the debounce fire and would scroll into permanently unloaded
  /// territory. Landing on a channel with nothing cached forces a fetch
  /// instead, at most this often.
  static const _blindThrottle = Duration(milliseconds: 500);
  DateTime? _lastBlindLoad;

  void _scheduleVisibleLoad() {
    _loadTimer?.cancel();
    if (_ready && _vm.unfilteredProgramsForChannel(_centeredId).isEmpty) {
      final now = DateTime.now();
      final last = _lastBlindLoad;
      if (last == null || now.difference(last) >= _blindThrottle) {
        _lastBlindLoad = now;
        unawaited(_loadVisible());
        return;
      }
    }
    _loadTimer = Timer(_debounce, () => unawaited(_loadVisible()));
  }

  Future<void> _loadVisible() async {
    if (!_ready || !mounted) return;
    if (_loadingVisible) {
      _loadAgain = true;
      return;
    }
    _loadingVisible = true;
    try {
      await _vm.ensureProgramsForChannels(_neighborhood());
      if (mounted) _vm.scheduleBoundaryRefresh();
    } catch (_) {
      // Keep cached cards when a newly visible channel cannot be loaded.
    } finally {
      _loadingVisible = false;
      if (mounted && _loadAgain) {
        _loadAgain = false;
        _scheduleVisibleLoad();
      }
    }
  }

  void _scheduleQuarterRefresh() {
    _quarterTimer?.cancel();
    final now = DateTime.now();
    final next = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      (now.minute ~/ 15 + 1) * 15,
    );
    _quarterTimer = Timer(next.difference(now), () {
      unawaited(_vm.refreshAtQuarterHour());
      _scheduleQuarterRefresh();
    });
  }

  void _scheduleHeader() {
    _headerTimer?.cancel();
    _headerTimer = Timer(_debounce, () {
      if (_scrolling) {
        _scheduleHeader();
        return;
      }
      setState(() {
        _headerChannel = _vm.channelForId(_centeredId);
        _headerProgram = _currentProgram(_centeredId);
      });
    });
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.horizontal) return false;
    if (notification is ScrollStartNotification) {
      _scrolling = true;
      _scheduleHeader();
    } else if (notification is ScrollEndNotification) {
      _scrolling = false;
      _scheduleHeader();
    }
    return false;
  }

  void _resetInactivity() {
    _hideTimer?.cancel();
    if (!_dismissed) _hideTimer = Timer(widget.inactivityDuration, _dismiss);
  }

  void _dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    _hideTimer?.cancel();
    widget.onDismiss();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    _resetInactivity();
    if (event.logicalKey.isBackKey) {
      if (event is KeyDownEvent) _dismiss();
      return KeyEventResult.handled;
    }
    if (event.logicalKey.isDownKey) {
      if (event is KeyDownEvent) {
        _dismissed = true;
        _hideTimer?.cancel();
        widget.onShowControls();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  GuideProgram? _currentProgram(String channelId, [DateTime? at]) {
    final now = at ?? DateTime.now();
    for (final program in _vm.unfilteredProgramsForChannel(channelId)) {
      if (!now.isBefore(program.startDate) && now.isBefore(program.endDate)) {
        return program;
      }
    }
    return null;
  }

  /// [GuideFilter] is localised here, at the UI edge, so the data layer stays
  /// language-free.
  String _filterLabel(GuideFilter filter) {
    final l10n = AppLocalizations.of(context);
    return switch (filter) {
      GuideFilter.all => l10n.all,
      GuideFilter.movies => l10n.movies,
      GuideFilter.series => l10n.series,
      GuideFilter.sports => l10n.sports,
      GuideFilter.news => l10n.news,
      GuideFilter.kids => l10n.kids,
      GuideFilter.premiere => l10n.premiere,
      GuideFilter.favorites => l10n.favorites,
    };
  }

  List<String> _categoryLabels(GuideProgram program) => [
    for (final tag in program.categoryTags) _filterLabel(tag),
  ];

  String _timeRange(GuideProgram program) =>
      '${TimeOfDay.fromDateTime(program.startDate).format(context)} - '
      '${TimeOfDay.fromDateTime(program.endDate).format(context)}';

  ChannelCarouselEntry _entry(GuideChannel channel, DateTime now) {
    final program = _currentProgram(channel.id, now);
    return ChannelCarouselEntry(
      channelId: channel.id,
      channelNumber: channel.number,
      channelName: channel.name,
      logoUrl: channel.imageTag == null
          ? null
          : _vm.imageApi.getPrimaryImageUrl(
              channel.id,
              maxHeight: 80,
              tag: channel.imageTag,
            ),
      isFavorite: channel.isFavorite,
      programTitle: program?.name,
      timeLabel: program == null ? null : _timeRange(program),
      rating: program?.officialRating,
      tags: program == null ? const [] : _categoryLabels(program),
      genre: program == null ? null : epgGenreFor(program),
      isLive: program != null,
      progress: program?.progressAt(now) ?? 0,
      hasTimer: program?.hasTimer == true || program?.hasSeriesTimer == true,
      programLoading:
          program == null &&
          _vm.loadStateFor(channel.id) != GuideChannelLoadState.loaded,
    );
  }

  Widget _header() {
    final channel = _headerChannel;
    final program = _headerProgram;
    if (channel == null) return const SizedBox.shrink();
    final season = program?.rawData['ParentIndexNumber'];
    final episode = program?.rawData['IndexNumber'];
    final suffix = season != null && episode != null
        ? ' (S$season:E$episode)'
        : '';
    return Container(
      key: const ValueKey('carousel-program-header'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        // The raised surface rather than the base one: the panel sits where
        // the scrim gradient is still almost clear, so it stays near-opaque
        // for the overview's sake while reading lighter than the strip.
        color: AppColorScheme.surfaceVariant.withValues(alpha: 0.85),
        borderRadius: AppRadius.circular(12),
        border: Border.fromBorderSide(ThemeRegistry.active.borders.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${program?.name ?? channel.name}$suffix',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            [
              if (program != null) _timeRange(program),
              [channel.number, channel.name].whereType<String>().join('  '),
              if (program?.officialRating?.trim() case final String rating
                  when rating.isNotEmpty)
                rating,
              if (program != null) ..._categoryLabels(program),
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          if (program?.overview case final String overview) ...[
            const SizedBox(height: 4),
            Text(
              overview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 13,
                height: 1.2,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _overlayFocus,
    onKeyEvent: _onKey,
    child: Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        // 24 dp of bottom margin sits inside the 5% TV overscan allowance
        // (27 dp of a 540 dp viewport) while dropping the whole overlay
        // closer to the screen edge.
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.94)],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final visible = ChannelCarouselCard.layoutFor(constraints.maxWidth)
                .count;
            if (_visibleCards != visible) {
              _visibleCards = visible;
              _scheduleVisibleLoad();
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: _headerHeight, child: _header()),
                const SizedBox(height: 16),
                if (_ready && _channels.isNotEmpty)
                  NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    child: ChannelCarousel(
                      channels: _currentEntries,
                      selectionRevision: widget.selectionRevision,
                      initialIndex: math.max(
                        0,
                        _channels.indexWhere(
                          (channel) => channel.id == _centeredId,
                        ),
                      ),
                      onChannelCentered: _centered,
                      onChannelSelected: (entry) =>
                          widget.onChannelSelected(entry.channelId),
                      onBack: _dismiss,
                      onKeyInteraction: _resetInactivity,
                    ),
                  )
                else
                  const SizedBox(height: ChannelCarouselCard.cardHeight),
              ],
            );
          },
        ),
      ),
    ),
  );
}

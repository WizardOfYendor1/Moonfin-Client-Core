import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';

import '../../../data/viewmodels/live_tv_guide_view_model.dart';
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
  late final LiveTvGuideViewModel _vm;
  late List<GuideChannel> _channels;
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
    _clockTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
    _scheduleQuarterRefresh();
    unawaited(_load());
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
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _vm.scheduleBoundaryRefresh();
      _scheduleQuarterRefresh();
      _scheduleHeader();
      setState(() {});
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
    setState(() {});
    if (_ready) _scheduleHeader();
  }

  void _centered(int index) {
    _centeredId = _channels[index].id;
    _scheduleHeader();
    _scheduleVisibleLoad();
  }

  void _scheduleVisibleLoad() {
    _loadTimer?.cancel();
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

  GuideProgram? _currentProgram(String channelId) {
    final now = DateTime.now();
    for (final program in _vm.unfilteredProgramsForChannel(channelId)) {
      if (!now.isBefore(program.startDate) && now.isBefore(program.endDate)) {
        return program;
      }
    }
    return null;
  }

  String _timeRange(GuideProgram program) =>
      '${TimeOfDay.fromDateTime(program.startDate).format(context)} - '
      '${TimeOfDay.fromDateTime(program.endDate).format(context)}';

  ChannelCarouselEntry _entry(GuideChannel channel) {
    final program = _currentProgram(channel.id);
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
      genre: program == null ? null : epgGenreFor(program),
      isLive: program != null,
      progress: program?.progressAt(DateTime.now()) ?? 0,
      hasTimer: program?.hasTimer == true || program?.hasSeriesTimer == true,
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
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
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (program != null) _timeRange(program),
              [channel.number, channel.name].whereType<String>().join('  '),
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          if (program?.overview case final String overview) ...[
            const SizedBox(height: 8),
            Text(
              overview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 13,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Focus(
    onKeyEvent: _onKey,
    child: Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.94)],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final visible = math.max(
              1,
              (constraints.maxWidth / ChannelCarouselCard.cardPitch).floor(),
            );
            if (_visibleCards != visible) {
              _visibleCards = visible;
              _scheduleVisibleLoad();
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: 150, child: _header()),
                const SizedBox(height: 16),
                if (_ready && _channels.isNotEmpty)
                  NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    child: ChannelCarousel(
                      channels: _channels.map(_entry).toList(),
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

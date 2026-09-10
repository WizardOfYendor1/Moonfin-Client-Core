import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../screens/livetv/epg/epg_genre.dart';

/// One channel in the quick channel carousel. Pure presentation: the host
/// owns scrolling, focus, and data — this only renders what it is given.
/// [centered] marks the card pinned at the viewport centre, which gets an
/// accent border and focus glow instead of the plain card border.
///
/// The programme block mirrors the guide cell: a top-aligned regular-weight
/// title over a muted metadata line. The card is far taller than a guide row,
/// so it spends the extra height on a second title line instead of dropping
/// the metadata.
class ChannelCarouselCard extends StatelessWidget {
  static const String _metaSeparator = ' · ';

  /// Text metrics are identical across every card in a frame, so measuring is
  /// memoised: a card build otherwise lays out up to seven [TextPainter]s.
  static final Map<(String, TextStyle, TextScaler), double> _metrics = {};
  static const int _metricsCap = 1024;

  final String? channelNumber;
  final String channelName;
  final String? logoUrl;
  final bool isFavorite;
  final String? programTitle;

  /// Broadcast window (`8:00 PM - 9:00 PM`); first item of the metadata line.
  final String? timeLabel;

  /// Official rating (`TV-14`), shown after the time.
  final String? rating;

  /// Localised category labels (`Sports`, `News`), shown after the rating.
  final List<String> tags;

  final EpgGenre? genre;
  final bool isLive;
  final double progress; // 0..1, meaningful only when isLive
  final bool hasTimer;
  final bool centered;

  static const double cardWidth = 168;
  static const double cardHeight = 108;
  static const double cardSpacing = 12;
  static const double cardPitch = cardWidth + cardSpacing;
  static const double _radius = 10;

  /// Full-bleed genre bar down the leading edge.
  static const double _genreBarWidth = 4;

  static const double _logoSize = 28;
  static const double _headerGap = 6;
  static const double _statusGap = 3;

  const ChannelCarouselCard({
    super.key,
    required this.channelNumber,
    required this.channelName,
    this.logoUrl,
    required this.isFavorite,
    required this.programTitle,
    required this.timeLabel,
    this.rating,
    this.tags = const [],
    required this.genre,
    required this.isLive,
    required this.progress,
    required this.hasTimer,
    required this.centered,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final borders = ThemeRegistry.active.borders;
    final accent = AppColorScheme.accent;
    final accentColor = genre?.color ?? accent;
    final muted = AppColorScheme.onSurface.withValues(alpha: 0.6);

    // Regular weight throughout: the centred card already reads from its
    // accent border and glow.
    final titleStyle = (textTheme.bodySmall ?? const TextStyle()).copyWith(
      fontWeight: FontWeight.w400,
      color: AppColorScheme.onSurface,
    );
    final metaStyle = (textTheme.labelSmall ?? const TextStyle(fontSize: 10))
        .copyWith(color: muted);
    // One step up from bodyMedium: the card is 168x108, so the channel name
    // can afford the extra 2 dp without pushing the programme block.
    final nameStyle = (textTheme.titleMedium ?? const TextStyle()).copyWith(
      fontWeight: FontWeight.w600,
      color: AppColorScheme.onSurface,
    );

    return SizedBox(
      width: cardWidth,
      height: cardHeight,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColorScheme.surface.withValues(alpha: 0.55),
          borderRadius: AppRadius.circular(_radius),
          border: Border.fromBorderSide(
            centered
                ? borders.focusBorder.copyWith(color: accent)
                : borders.cardBorder,
          ),
          boxShadow: centered ? borders.focusGlow : null,
        ),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(width: _genreBarWidth, color: accentColor),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: LayoutBuilder(
                builder: (context, box) {
                  final scaler = MediaQuery.textScalerOf(context);
                  final titleLine = _lineHeight(titleStyle, scaler);
                  final metaLine = _lineHeight(metaStyle, scaler);
                  final headerHeight = math.max(
                    _logoSize,
                    _lineHeight(nameStyle, scaler),
                  );
                  final belowHeader = box.maxHeight.isFinite
                      ? box.maxHeight - headerHeight - _headerGap
                      : double.infinity;

                  final metaItems = _fittingMeta(
                    box.maxWidth,
                    metaStyle,
                    scaler,
                  );
                  final showMeta =
                      metaItems.isNotEmpty &&
                      belowHeader >= titleLine + metaLine;
                  // The card has room to wrap and keep the metadata; only a
                  // scaled-up text size takes the second line back.
                  final wrapTitle =
                      programTitle != null &&
                      belowHeader >=
                          2 * titleLine + (showMeta ? metaLine : 0.0);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _headerRow(nameStyle, metaStyle),
                      const SizedBox(height: _headerGap),
                      if (programTitle != null)
                        Text(
                          programTitle!,
                          maxLines: wrapTitle ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle,
                        ),
                      if (showMeta)
                        Text(
                          metaItems.join(_metaSeparator),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                          style: metaStyle,
                        ),
                    ],
                  );
                },
              ),
            ),
            // Progress reads as a seekbar, not as card structure: range tokens
            // rather than the genre colour, inset from the genre bar and from
            // both card edges so it never looks like a border.
            if (isLive && progress > 0)
              Positioned(
                left: _genreBarWidth + AppSpacing.spaceSm,
                right: AppSpacing.spaceSm,
                bottom: AppSpacing.spaceSm,
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 4,
                  borderRadius: AppRadius.circular(2),
                  backgroundColor: AppColorScheme.rangeTrack,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppColorScheme.rangeProgress,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _headerRow(TextStyle nameStyle, TextStyle numberStyle) => Row(
    children: [
      if (isFavorite || hasTimer) ...[
        _statusCluster(),
        const SizedBox(width: _statusGap),
      ],
      _logo(),
      const SizedBox(width: 8),
      Expanded(
        child: Row(
          children: [
            if (channelNumber != null) ...[
              Text(
                channelNumber!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: numberStyle,
              ),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                channelName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: nameStyle,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  /// Favourite and recording status, pinned to the card's top-left corner so
  /// it reads as state rather than as part of the channel or programme text.
  Widget _statusCluster() => SizedBox(
    height: _logoSize,
    child: Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isFavorite)
              const Icon(Icons.favorite, size: 11, color: AppColors.red500),
            if (isFavorite && hasTimer) const SizedBox(width: _statusGap),
            if (hasTimer)
              const Icon(
                Icons.fiber_manual_record,
                size: 9,
                color: Color(0xFFE0685C),
              ),
          ],
        ),
      ],
    ),
  );

  /// Metadata that fits the given width — time, then rating, then tags —
  /// dropping from the end once the line is full.
  List<String> _fittingMeta(double width, TextStyle style, TextScaler scaler) {
    final items = <String>[
      for (final item in [timeLabel, rating, ...tags])
        if (item != null && item.trim().isNotEmpty) item.trim(),
    ];
    if (items.isEmpty) return const [];
    if (!width.isFinite) return items;

    final fitted = <String>[];
    var used = 0.0;
    for (final item in items) {
      final piece = fitted.isEmpty ? item : '$_metaSeparator$item';
      final pieceWidth = _textWidth(piece, style, scaler);
      if (used + pieceWidth > width) break;
      used += pieceWidth;
      fitted.add(item);
    }
    return fitted;
  }

  static double _measure(
    String cacheKey,
    String text,
    TextStyle style,
    TextScaler scaler,
    double Function(TextPainter) pick,
  ) {
    final key = (cacheKey, style, scaler);
    final cached = _metrics[key];
    if (cached != null) return cached;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final value = pick(painter);
    painter.dispose();
    if (_metrics.length >= _metricsCap) _metrics.clear();
    _metrics[key] = value;
    return value;
  }

  static double _lineHeight(TextStyle style, TextScaler scaler) =>
      _measure('h', 'Ag', style, scaler, (p) => p.height.ceilToDouble());

  static double _textWidth(String text, TextStyle style, TextScaler scaler) =>
      _measure('w$text', text, style, scaler, (p) => p.width);

  Widget _logo() {
    if (logoUrl == null || logoUrl!.isEmpty) return _logoFallback(_logoSize);
    return ClipRRect(
      borderRadius: AppRadius.circular(4),
      child: CachedNetworkImage(
        imageUrl: logoUrl!,
        width: _logoSize,
        height: _logoSize,
        fit: BoxFit.contain,
        errorWidget: (context, url, error) => _logoFallback(_logoSize),
      ),
    );
  }

  Widget _logoFallback(double size) => SizedBox(
    width: size,
    height: size,
    child: Icon(
      Icons.tv,
      size: 16,
      color: AppColorScheme.onSurface.withValues(alpha: 0.4),
    ),
  );
}

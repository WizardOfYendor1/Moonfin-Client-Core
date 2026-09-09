import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../screens/livetv/epg/epg_genre.dart';

/// One channel in the quick channel carousel. Pure presentation: the host
/// owns scrolling, focus, and data — this only renders what it is given.
/// [centered] marks the card pinned at the viewport centre, which gets an
/// accent border and focus glow instead of the plain card border.
class ChannelCarouselCard extends StatelessWidget {
  final String? channelNumber;
  final String channelName;
  final String? logoUrl;
  final bool isFavorite;
  final String? programTitle;
  final String? timeLabel;
  final EpgGenre? genre;
  final bool isLive;
  final double progress; // 0..1, meaningful only when isLive
  final bool hasTimer;
  final bool centered;

  static const double _width = 168;
  static const double _height = 108;
  static const double _radius = 10;

  const ChannelCarouselCard({
    super.key,
    required this.channelNumber,
    required this.channelName,
    this.logoUrl,
    required this.isFavorite,
    required this.programTitle,
    required this.timeLabel,
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

    return SizedBox(
      width: _width,
      height: _height,
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
              child: Container(width: 4, color: accentColor),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
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
                                style: textTheme.labelSmall
                                    ?.copyWith(color: muted),
                              ),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: Text(
                                channelName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isFavorite) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.favorite,
                            size: 12,
                            color: AppColorScheme.onSurface
                                .withValues(alpha: 0.85)),
                      ],
                      if (hasTimer) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.fiber_manual_record,
                            size: 9, color: Color(0xFFE0685C)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (programTitle != null)
                    Text(
                      programTitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall,
                    ),
                  if (timeLabel != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      timeLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.copyWith(color: muted),
                    ),
                  ],
                ],
              ),
            ),
            if (isLive)
              Positioned(
                left: 4,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 3,
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _logo() {
    const size = 28.0;
    if (logoUrl == null || logoUrl!.isEmpty) return _logoFallback(size);
    return ClipRRect(
      borderRadius: AppRadius.circular(4),
      child: CachedNetworkImage(
        imageUrl: logoUrl!,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorWidget: (context, url, error) => _logoFallback(size),
      ),
    );
  }

  Widget _logoFallback(double size) => SizedBox(
        width: size,
        height: size,
        child: Icon(Icons.tv,
            size: 16, color: AppColorScheme.onSurface.withValues(alpha: 0.4)),
      );
}

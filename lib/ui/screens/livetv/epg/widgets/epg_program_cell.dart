import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../epg_genre.dart';

/// A single program in the guide grid. Pure presentation: the host positions it
/// (left/width along the timeline) and owns focus, passing [focused]. The genre
/// shows as a colored left bar on Material and a subtle dot on Apple; the on-now
/// program gets a progress bar, scheduled recordings a red dot.
///
/// [placeholderLabel] renders centered muted text over neutral filler, for a
/// real schedule gap; leave it null for a genre-filtered hole, which must stay
/// unlabelled. [loading] and [failed] override everything else with their own
/// treatment for a non-program placeholder cell spanning the whole row.
class EpgProgramCell extends StatelessWidget {
  final String title;

  /// Retained for API compatibility only — the cell no longer renders it.
  final String? timeLabel;
  final EpgGenre genre;
  final bool isLive;
  final bool isPast;
  final double progress; // 0..1
  final bool hasTimer;
  final bool focused;
  final bool apple;

  /// Retained for API compatibility only — nothing is gated on it now.
  final bool showMeta;
  final String? placeholderLabel;
  final bool loading;
  final bool failed;
  final double textLeftPadding;

  /// Programme started before the visible window's left edge; shows a `<<`
  /// marker that survives even when the title has no room at all.
  final bool startsBeforeWindow;

  const EpgProgramCell({
    super.key,
    required this.title,
    required this.timeLabel,
    required this.genre,
    required this.isLive,
    this.isPast = false,
    required this.progress,
    required this.hasTimer,
    required this.focused,
    required this.apple,
    this.showMeta = true,
    this.placeholderLabel,
    this.loading = false,
    this.failed = false,
    this.textLeftPadding = 0,
    this.startsBeforeWindow = false,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final accent = AppColorScheme.accent;
    final muted = AppColorScheme.onSurface.withValues(alpha: 0.55);
    final radius = apple ? 12.0 : 6.0;

    final Color bg;
    if (focused) {
      bg = apple
          ? Colors.white.withValues(alpha: 0.18)
          : const Color(0xFF1C2C3C);
    } else if (apple) {
      bg = Colors.white.withValues(alpha: 0.06);
    } else {
      bg = isLive
          ? genre.color.withValues(alpha: 0.14)
          : AppColorScheme.surface.withValues(alpha: 0.5);
    }

    final focusBorder = focused
        ? Border.all(color: accent, width: apple ? 1.5 : 2)
        : null;

    // Loading and failed placeholders span the whole row while programs are
    // unresolved for this channel; both override the normal program layout.
    if (loading) {
      return Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: AppRadius.circular(radius),
          border: focusBorder,
        ),
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: muted),
          ),
        ),
      );
    }
    if (failed) {
      final errorColor = AppColorScheme.statusError;
      return Container(
        decoration: BoxDecoration(
          color: errorColor.withValues(alpha: 0.12),
          borderRadius: AppRadius.circular(radius),
          border:
              focusBorder ??
              Border.all(color: errorColor.withValues(alpha: 0.4)),
        ),
        child: Center(child: Icon(Icons.refresh, size: 16, color: errorColor)),
      );
    }

    final titleStyle = (textTheme.bodySmall ?? const TextStyle()).copyWith(
      fontWeight: placeholderLabel != null
          ? FontWeight.w400
          : (focused || isLive ? FontWeight.w600 : FontWeight.w400),
      color: placeholderLabel != null ? muted : AppColorScheme.onSurface,
    );

    final markerStyle = titleStyle.copyWith(
      fontWeight: FontWeight.w700,
      color: AppColorScheme.onSurface.withValues(alpha: 0.7),
    );
    final showMarker = startsBeforeWindow && placeholderLabel == null;

    // Structural boundary marker: full-bleed, hard-edged, genre-tinted.
    const separatorWidth = 3.0;

    final programCell = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.circular(radius),
        border: focusBorder,
      ),
      child: Stack(
        children: [
          if (!apple)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: separatorWidth,
                color: genre.color.withValues(
                  alpha: focused || isLive ? 0.9 : 0.5,
                ),
              ),
            ),
          LayoutBuilder(
            builder: (context, cell) => Padding(
              // A marker cell this narrow gives up its inset so `<<` still fits.
              padding: showMarker && cell.maxWidth < 48
                  ? EdgeInsets.fromLTRB(2 + textLeftPadding, 4, 2, 4)
                  : EdgeInsets.fromLTRB(
                      (apple ? 10 : 12) + textLeftPadding,
                      4,
                      8,
                      4,
                    ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  showMarker
                      ? _markerRow(context, titleStyle, markerStyle)
                      : Row(
                          children: [
                            if (apple) ...[
                              _genreDot(),
                              const SizedBox(width: 6),
                            ],
                            Flexible(
                              child: Text(
                                placeholderLabel ?? title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: titleStyle,
                              ),
                            ),
                            if (hasTimer) ...[
                              const SizedBox(width: 6),
                              _timerDot(),
                            ],
                          ],
                        ),
                ],
              ),
            ),
          ),
          // Progress reads as a seekbar, not as cell structure: range tokens
          // rather than the genre colour, on its own visible track, and inset
          // past the boundary marker so the two never merge.
          if (isLive && progress > 0)
            Positioned(
              left: apple ? 0 : separatorWidth,
              right: 0,
              bottom: 0,
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: AppColorScheme.rangeTrack,
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppColorScheme.rangeProgress,
                ),
              ),
            ),
        ],
      ),
    );

    return isPast ? Opacity(opacity: 0.55, child: programCell) : programCell;
  }

  Widget _genreDot() => Container(
    width: 6,
    height: 6,
    decoration: BoxDecoration(color: genre.color, shape: BoxShape.circle),
  );

  Widget _timerDot() =>
      const Icon(Icons.fiber_manual_record, size: 9, color: Color(0xFFE0685C));

  /// Width-priority title row for a programme that started before the window:
  /// every slot is measured and allotted in order, so the `<<` marker is served
  /// before the title and cannot be squeezed out or overflow the row.
  Widget _markerRow(
    BuildContext context,
    TextStyle titleStyle,
    TextStyle markerStyle,
  ) {
    final scaler = MediaQuery.textScalerOf(context);
    final markerWidth = _textWidth('<<', markerStyle, scaler);

    return LayoutBuilder(
      builder: (context, constraints) {
        var remaining = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : double.infinity;
        double take(double want) {
          final got = want.clamp(0.0, remaining);
          remaining -= got;
          return got;
        }

        final dot = apple ? take(12) : 0.0;
        final marker = take(markerWidth);
        final gap = take(4);
        final timer = hasTimer ? take(15) : 0.0;
        final titleWidth = remaining.isFinite ? remaining : double.infinity;

        return Row(
          children: [
            if (apple)
              SizedBox(
                width: dot,
                child: Center(child: _genreDot()),
              ),
            SizedBox(
              width: marker,
              child: Text(
                '<<',
                maxLines: 1,
                softWrap: false,
                style: markerStyle,
              ),
            ),
            SizedBox(width: gap),
            SizedBox(
              width: titleWidth,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
            ),
            if (hasTimer)
              SizedBox(
                width: timer,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _timerDot(),
                ),
              ),
          ],
        );
      },
    );
  }

  static double _textWidth(String text, TextStyle style, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}

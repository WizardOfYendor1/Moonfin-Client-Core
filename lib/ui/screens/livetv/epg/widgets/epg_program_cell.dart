import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../epg_genre.dart';

/// A single program in the guide grid. Pure presentation: the host positions it
/// (left/width along the timeline) and owns focus, passing [focused]. The genre
/// shows as a colored left bar on Material and a subtle dot on Apple; the on-now
/// program gets a LIVE badge + progress, scheduled recordings a red dot.
///
/// [placeholderLabel] renders centered muted text over neutral filler, for a
/// real schedule gap; leave it null for a genre-filtered hole, which must stay
/// unlabelled. [loading] and [failed] override everything else with their own
/// treatment for a non-program placeholder cell spanning the whole row.
class EpgProgramCell extends StatelessWidget {
  final String title;
  final String? timeLabel;
  final EpgGenre genre;
  final bool isLive;
  final bool isPast;
  final double progress; // 0..1
  final bool hasTimer;
  final bool focused;
  final bool apple;
  final bool showMeta; // false for very narrow cells
  final String? placeholderLabel;
  final bool loading;
  final bool failed;
  final double textLeftPadding;

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
              child: Container(width: 4, color: genre.color),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              (apple ? 10 : 12) + textLeftPadding,
              4,
              8,
              4,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    if (apple) ...[
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: genre.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (isLive && showMeta) ...[
                      _liveBadge(genre.color),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        placeholderLabel ?? title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: placeholderLabel != null
                              ? FontWeight.w400
                              : (focused || isLive
                                    ? FontWeight.w600
                                    : FontWeight.w400),
                          color: placeholderLabel != null
                              ? muted
                              : AppColorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (hasTimer) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.fiber_manual_record,
                        size: 9,
                        color: Color(0xFFE0685C),
                      ),
                    ],
                  ],
                ),
                if (showMeta && timeLabel != null) ...[
                  const SizedBox(height: 2),
                  // Flexible so a scaled-up label is clipped by the row rather
                  // than overflowing it; maxLines stops it wrapping when narrow.
                  Flexible(
                    child: Text(
                      timeLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.copyWith(color: muted),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isLive && progress > 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 3,
                backgroundColor: Colors.white.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation<Color>(
                  apple ? accent : genre.color,
                ),
              ),
            ),
        ],
      ),
    );

    return isPast ? Opacity(opacity: 0.55, child: programCell) : programCell;
  }

  Widget _liveBadge(Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: color,
      borderRadius: AppRadius.circular(4),
    ),
    child: const Text(
      'LIVE',
      style: TextStyle(
        fontSize: 8.5,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    ),
  );
}

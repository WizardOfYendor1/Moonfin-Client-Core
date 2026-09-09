import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

/// Channel identity cell for the guide rail: logo tile pinned left, with the
/// accent number chip and the channel name right-justified against the cell's
/// trailing edge. Pure presentation; the host owns focus + key handling and
/// passes [focused]. Idiom-aware surface (glass-tinted on Apple, accent tint on
/// Material).
class EpgChannelCell extends StatelessWidget {
  final String? logoUrl;
  final String name;
  final String? number;
  final bool focused;
  final bool apple;

  /// Marks the channel as a favourite with a red heart beside the number.
  final bool isFavorite;

  const EpgChannelCell({
    super.key,
    required this.logoUrl,
    required this.name,
    required this.number,
    required this.focused,
    required this.apple,
    this.isFavorite = false,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final accent = AppColorScheme.accent;
    final radius = apple ? 14.0 : 10.0;
    final Color bg;
    if (focused) {
      bg = apple
          ? Colors.white.withValues(alpha: 0.16)
          : accent.withValues(alpha: 0.16);
    } else {
      bg = apple ? Colors.white.withValues(alpha: 0.06) : Colors.transparent;
    }

    final nameStyle = textTheme.titleSmall?.copyWith(
      fontWeight: focused ? FontWeight.w600 : FontWeight.w500,
      color: AppColorScheme.onSurface,
    );

    final chip = number == null ? null : _numberChip(number!, accent);
    final hasTopRow = chip != null || isFavorite;

    final body = Row(
      children: [
        _logo(30, radius),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (hasTopRow) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (isFavorite) ...[
                      const Icon(
                        Icons.favorite,
                        size: 11,
                        color: AppColors.red500,
                      ),
                      const SizedBox(width: 4),
                    ],
                    ?chip,
                  ],
                ),
                const SizedBox(height: 3),
              ],
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: nameStyle,
              ),
            ],
          ),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.circular(radius),
        // Always reserve the border so focus does not change the cell height.
        border: Border.all(
          color: focused ? accent.withValues(alpha: 0.7) : Colors.transparent,
          width: 1,
        ),
      ),
      child: body,
    );
  }

  Widget _logo(double size, double radius) => SizedBox(
    width: size,
    height: size,
    child: ClipRRect(
      borderRadius: AppRadius.circular(radius * 0.6),
      child: (logoUrl != null && logoUrl!.isNotEmpty)
          ? CachedNetworkImage(
              imageUrl: logoUrl!,
              fit: BoxFit.contain,
              errorWidget: (context, url, error) => _fallback(),
            )
          : _fallback(),
    ),
  );

  Widget _fallback() => Icon(
    Icons.tv,
    size: 16,
    color: AppColorScheme.onSurface.withValues(alpha: 0.4),
  );

  Widget _numberChip(String number, Color accent) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
    decoration: BoxDecoration(
      color: focused
          ? accent
          : AppColorScheme.onSurface.withValues(alpha: 0.12),
      borderRadius: AppRadius.circular(7),
    ),
    child: Text(
      number,
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w600,
        color: focused
            ? const Color(0xFF062430)
            : AppColorScheme.onSurface.withValues(alpha: 0.85),
      ),
    ),
  );
}
